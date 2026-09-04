// TWin AR — Phase 8.7.1 seed/catalogue product image migration core logic.
//
// Pure/injectable functions only — no direct firebase-admin usage here, so
// this module can be unit-tested with fake Firestore/Storage adapters. The
// CLI entry point (migrate_product_images.mjs) wires this up to the real
// Admin SDK.
//
// Scope (see README.md for the full rationale): migrates ONLY
// ProductImageRef entries with source === 'asset' found in the live
// Firestore `products` collection's `mainImage`/`galleryMedia` fields.
// Never touches logos/icons/onboarding art, avatars, AR/VTO assets, or
// anything outside those two fields.

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

export const MAX_PRODUCT_IMAGE_BYTES = 10 * 1024 * 1024; // matches storage.rules

export const CONTENT_TYPE_BY_EXTENSION = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
};

export const CONFIRMED_PROJECT_ID = 'twin-ar-d4d75';

/**
 * Deterministic, content-addressed object name. Identical file bytes always
 * produce the same name, which is what makes re-running the migration
 * idempotent and collapses a single product's own repeated gallery
 * references to the same source file into one uploaded object for that
 * product. This is per-product dedup only — `storageObjectPath` below
 * prefixes every object with `{productId}`, so the same source file shared
 * across DIFFERENT products still uploads one object per product, not one
 * globally.
 */
export function computeStableFileName(buffer, extension) {
  const hash = createHash('sha256').update(buffer).digest('hex').slice(0, 16);
  return `img-${hash}${extension}`;
}

export function storageObjectPath(productId, stableFileName) {
  return `products/${productId}/images/${stableFileName}`;
}

/**
 * Same REST download-URL shape Firebase's client SDK `getDownloadURL()`
 * returns (`.../o/<encoded path>?alt=media`), minus the `&token=` query
 * param — unnecessary here because `storage.rules` already makes
 * `products/{id}/images/{imageId}` public-read (`allow read: if true`), so
 * no token-based bypass is needed. `ProductImageView`/the Firestore mapper
 * only ever treat this as an opaque URL string, so this representation is a
 * drop-in for the pre-existing `ProductImageSource.network` contract.
 */
export function buildPublicUrl(bucketName, objectPath) {
  const encodedPath = encodeURIComponent(objectPath);
  return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucketName)}/o/${encodedPath}?alt=media`;
}

/**
 * Validates one local asset file against the same MIME/size rules
 * `storage.rules` enforces for product images. Returns either
 * `{ ok: true, buffer, size, contentType, extension }` or
 * `{ ok: false, reason }` — never throws, so callers can collect failures
 * across a whole product without a try/catch per file.
 */
export function validateAssetFile(repoRoot, relativePath) {
  const extension = path.extname(relativePath).toLowerCase();
  const contentType = CONTENT_TYPE_BY_EXTENSION[extension];
  if (!contentType) {
    return {
      ok: false,
      reason: `Unsupported file extension "${extension || '(none)'}" — only .jpg/.jpeg/.png/.webp are allowed.`,
    };
  }

  const absolutePath = path.join(repoRoot, relativePath);
  if (!existsSync(absolutePath)) {
    return { ok: false, reason: `File not found: ${relativePath}` };
  }

  const stat = statSync(absolutePath);
  if (!stat.isFile()) {
    return { ok: false, reason: `Not a regular file: ${relativePath}` };
  }
  if (stat.size > MAX_PRODUCT_IMAGE_BYTES) {
    return {
      ok: false,
      reason: `File too large (${stat.size} bytes > ${MAX_PRODUCT_IMAGE_BYTES} byte limit): ${relativePath}`,
    };
  }
  if (stat.size === 0) {
    return { ok: false, reason: `File is empty: ${relativePath}` };
  }

  const buffer = readFileSync(absolutePath);
  return { ok: true, buffer, size: stat.size, contentType, extension };
}

/**
 * Classifies one ProductImageRef-shaped object ({path, source, altText}).
 * `source: 'network'` and unrecognized/`'file'` sources are always passed
 * through unchanged — this tool never touches anything but a valid `asset`
 * reference.
 */
export function analyzeImageRef(ref, repoRoot) {
  const originalRef = ref ?? { path: '', source: 'asset', altText: '' };
  const source = originalRef.source;

  if (source === 'network') {
    return { kind: 'network', originalRef };
  }
  if (source !== 'asset') {
    // 'file' (or any unrecognized value) should never be committed to
    // Firestore per this project's design — defensively pass it through
    // unchanged rather than guessing at a migration for it.
    return { kind: 'unexpected-source', originalRef, source };
  }

  const validation = validateAssetFile(repoRoot, originalRef.path);
  if (!validation.ok) {
    return { kind: 'asset-invalid', originalRef, reason: validation.reason };
  }

  const stableFileName = computeStableFileName(
    validation.buffer,
    validation.extension,
  );
  return {
    kind: 'asset-valid',
    originalRef,
    buffer: validation.buffer,
    contentType: validation.contentType,
    size: validation.size,
    stableFileName,
  };
}

/**
 * Builds the full migration plan for one product document. Enforces the
 * all-or-nothing-per-product rule: if ANY asset reference on this product
 * fails validation, `blocked` is true and `wouldChange` is false — none of
 * this product's images are migrated, even the individually-valid ones.
 */
export function planProduct(productId, data, repoRoot) {
  const mainImage = analyzeImageRef(data?.mainImage, repoRoot);
  const galleryMedia = (data?.galleryMedia ?? []).map((ref) =>
    analyzeImageRef(ref, repoRoot),
  );
  const allAnalyses = [mainImage, ...galleryMedia];

  const invalid = allAnalyses.filter((a) => a.kind === 'asset-invalid');
  const assetValidCount = allAnalyses.filter(
    (a) => a.kind === 'asset-valid',
  ).length;
  const networkSkipCount = allAnalyses.filter(
    (a) => a.kind === 'network',
  ).length;
  const unexpectedSourceCount = allAnalyses.filter(
    (a) => a.kind === 'unexpected-source',
  ).length;

  const blocked = invalid.length > 0;
  const wouldChange = !blocked && assetValidCount > 0;

  return {
    productId,
    mainImage,
    galleryMedia,
    invalid,
    assetValidCount,
    networkSkipCount,
    unexpectedSourceCount,
    blocked,
    wouldChange,
  };
}

/** Unique {stableFileName, objectPath, buffer, contentType} uploads a plan needs. */
export function collectUploadsForProduct(plan) {
  const seen = new Map();
  for (const analysis of [plan.mainImage, ...plan.galleryMedia]) {
    if (analysis.kind !== 'asset-valid') continue;
    if (!seen.has(analysis.stableFileName)) {
      seen.set(analysis.stableFileName, {
        stableFileName: analysis.stableFileName,
        objectPath: storageObjectPath(plan.productId, analysis.stableFileName),
        buffer: analysis.buffer,
        contentType: analysis.contentType,
      });
    }
  }
  return [...seen.values()];
}

/** Rebuilds a plan's mainImage/galleryMedia using resolved upload URLs. */
export function buildUpdatedFields(plan, urlByStableFileName) {
  const toRef = (analysis) => {
    if (analysis.kind === 'asset-valid') {
      return {
        path: urlByStableFileName.get(analysis.stableFileName),
        source: 'network',
        altText: analysis.originalRef.altText ?? '',
      };
    }
    return analysis.originalRef;
  };
  return {
    mainImage: toRef(plan.mainImage),
    galleryMedia: plan.galleryMedia.map(toRef),
  };
}

/**
 * Reads every product via `firestoreAdapter.listProducts()` and builds a
 * plan per product. Performs no writes — safe to call for both dry-run
 * reporting and as the read phase before an apply run.
 */
export async function buildFullPlan(firestoreAdapter, repoRoot) {
  const products = await firestoreAdapter.listProducts();
  return products.map(({ id, data }) => planProduct(id, data, repoRoot));
}

export function summarizePlans(plans) {
  const changing = plans.filter((p) => p.wouldChange);
  const blocked = plans.filter((p) => p.blocked);
  const untouched = plans.filter((p) => !p.wouldChange && !p.blocked);

  const missingOrInvalid = blocked.flatMap((p) =>
    p.invalid.map((a) => ({ productId: p.productId, path: a.originalRef.path, reason: a.reason })),
  );

  const plannedPaths = new Set();
  let assetReferencesFound = 0;
  let alreadyNetworkSkipped = 0;
  for (const p of plans) {
    assetReferencesFound += p.assetValidCount + p.invalid.length;
    alreadyNetworkSkipped += p.networkSkipCount;
    if (p.wouldChange) {
      for (const upload of collectUploadsForProduct(p)) {
        plannedPaths.add(upload.objectPath);
      }
    }
  }

  return {
    productsScanned: plans.length,
    assetReferencesFound,
    alreadyNetworkSkipped,
    missingOrInvalid,
    plannedPaths: [...plannedPaths].sort(),
    documentsThatWouldChange: changing.map((p) => p.productId),
    documentsBlocked: blocked.map((p) => p.productId),
    documentsUntouched: untouched.length,
  };
}

/**
 * Applies the migration for one already-validated, non-blocked plan:
 * uploads (or reuses) every distinct object it needs, then updates the
 * Firestore document. On any failure, best-effort deletes only objects this
 * call itself created (never a pre-existing/reused object), leaves the
 * document untouched, and rethrows so the caller can record the failure and
 * continue with the next product.
 */
export async function applyProductMigration(plan, { firestoreAdapter, storageAdapter }) {
  const uploads = collectUploadsForProduct(plan);
  const urlByStableFileName = new Map();
  const newlyCreatedObjectPaths = [];

  try {
    for (const upload of uploads) {
      const alreadyExists = await storageAdapter.exists(upload.objectPath);
      if (!alreadyExists) {
        await storageAdapter.upload(
          upload.objectPath,
          upload.buffer,
          upload.contentType,
        );
        newlyCreatedObjectPaths.push(upload.objectPath);
      }
      urlByStableFileName.set(
        upload.stableFileName,
        storageAdapter.publicUrl(upload.objectPath),
      );
    }

    const updatedFields = buildUpdatedFields(plan, urlByStableFileName);
    await firestoreAdapter.updateProduct(plan.productId, updatedFields);
    return { productId: plan.productId, ok: true, uploadedCount: newlyCreatedObjectPaths.length };
  } catch (err) {
    for (const objectPath of newlyCreatedObjectPaths) {
      try {
        await storageAdapter.delete(objectPath);
      } catch {
        // Best-effort only — never masks the original failure.
      }
    }
    return {
      productId: plan.productId,
      ok: false,
      error: err?.message ?? String(err),
      rolledBackObjectPaths: newlyCreatedObjectPaths,
    };
  }
}

/** Builds the backup payload written to disk before any apply-mode writes. */
export function buildBackupPayload(plans) {
  return plans
    .filter((p) => p.wouldChange)
    .map((p) => ({
      productId: p.productId,
      mainImage: p.mainImage.originalRef,
      galleryMedia: p.galleryMedia.map((a) => a.originalRef),
    }));
}

/**
 * Pure guard used by the CLI before it ever constructs a real Admin SDK
 * client for a live write. `apply`/`rollback-apply` modes must be given the
 * exact confirmed project id, matching `CONFIRMED_PROJECT_ID` — anything
 * else (missing, mistyped, or a different project) refuses to run.
 */
export function assertProjectGuard(mode, confirmedProjectId) {
  if (mode !== 'apply' && mode !== 'rollback-apply') return;
  if (confirmedProjectId !== CONFIRMED_PROJECT_ID) {
    throw new Error(
      `Refusing to run live writes: --project must be exactly "${CONFIRMED_PROJECT_ID}" ` +
        `(got ${confirmedProjectId ? `"${confirmedProjectId}"` : 'nothing'}). ` +
        'This guard exists so a copy-pasted command can never silently write to the wrong project.',
    );
  }
}

/** Restores every entry in a backup payload via a narrow field-only update. */
export async function applyRollback(backupPayload, firestoreAdapter) {
  const results = [];
  for (const entry of backupPayload) {
    try {
      await firestoreAdapter.updateProduct(entry.productId, {
        mainImage: entry.mainImage,
        galleryMedia: entry.galleryMedia,
      });
      results.push({ productId: entry.productId, ok: true });
    } catch (err) {
      results.push({
        productId: entry.productId,
        ok: false,
        error: err?.message ?? String(err),
      });
    }
  }
  return results;
}
