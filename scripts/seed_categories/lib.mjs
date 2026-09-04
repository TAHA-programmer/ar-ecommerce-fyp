// TWin AR — Phase 8.8 category seed core logic.
//
// Pure/injectable functions only - no direct firebase-admin usage here, so
// this module can be unit-tested with fake Firestore/Storage adapters,
// mirroring scripts/migrate_product_images/lib.mjs's structure.
//
// Seeds the five canonical categories from categories_seed.json (exported
// from lib/core/data/category_seed_data.dart via
// tool/export_category_seed.dart) by uploading each entry's bundled source
// image to Storage and creating its Firestore categories/{key} document -
// ONLY when that document does not already exist. An existing document
// (created by a prior seed run, or since edited by an Admin through the
// app) is left completely untouched on a normal rerun - see runSeed's doc
// comment for the --force override.

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

export const MAX_CATEGORY_IMAGE_BYTES = 5 * 1024 * 1024; // matches storage.rules

export const CONTENT_TYPE_BY_EXTENSION = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
};

export const CONFIRMED_PROJECT_ID = 'twin-ar-d4d75';

export function computeStableFileName(buffer, extension) {
  const hash = createHash('sha256').update(buffer).digest('hex').slice(0, 16);
  return `img-${hash}${extension}`;
}

export function storageObjectPath(categoryId, stableFileName) {
  return `categories/${categoryId}/images/${stableFileName}`;
}

/** Same REST download-URL shape as migrate_product_images/lib.mjs's buildPublicUrl. */
export function buildPublicUrl(bucketName, objectPath) {
  const encodedPath = encodeURIComponent(objectPath);
  return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucketName)}/o/${encodedPath}?alt=media`;
}

/** Validates one seed entry's local source image. Never throws - returns a result object. */
export function validateSeedImageFile(repoRoot, relativePath) {
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
  if (stat.size > MAX_CATEGORY_IMAGE_BYTES) {
    return {
      ok: false,
      reason: `File too large (${stat.size} bytes > ${MAX_CATEGORY_IMAGE_BYTES} byte limit): ${relativePath}`,
    };
  }
  if (stat.size === 0) {
    return { ok: false, reason: `File is empty: ${relativePath}` };
  }

  const buffer = readFileSync(absolutePath);
  return { ok: true, buffer, size: stat.size, contentType, extension };
}

/**
 * Seeds one category entry.
 *
 * - Validates its source image first; a validation failure aborts THIS
 *   entry only (no Firestore/Storage call made for it) and is reported to
 *   the caller - the other four entries are unaffected.
 * - If a document already exists at categories/{key} and `force` is not
 *   set, the entry is SKIPPED entirely (no upload, no write) - this is what
 *   guarantees a later Admin edit (rename, re-image, activate/deactivate)
 *   is never silently reverted by a routine rerun.
 * - Otherwise uploads the image (reusing an already-uploaded matching
 *   object via a content-hash object name, exactly like
 *   migrate_product_images) and creates/overwrites the document.
 * - If the Firestore write fails after a NEW upload, that upload (and only
 *   that upload - never a pre-existing/reused object) is best-effort rolled
 *   back.
 */
export async function seedOneCategory(
  entry,
  { repoRoot, firestoreAdapter, storageAdapter, force },
) {
  const validation = validateSeedImageFile(repoRoot, entry.sourceImageAssetPath);
  if (!validation.ok) {
    return { key: entry.key, ok: false, skipped: false, reason: validation.reason };
  }

  const existing = await firestoreAdapter.getCategory(entry.key);
  if (existing && !force) {
    return { key: entry.key, ok: true, skipped: true };
  }

  const stableFileName = computeStableFileName(validation.buffer, validation.extension);
  const objectPath = storageObjectPath(entry.key, stableFileName);

  let uploadedThisRun = false;
  try {
    const alreadyExists = await storageAdapter.exists(objectPath);
    if (!alreadyExists) {
      await storageAdapter.upload(objectPath, validation.buffer, validation.contentType);
      uploadedThisRun = true;
    }
    const imageUrl = storageAdapter.publicUrl(objectPath);

    await firestoreAdapter.createCategory(entry.key, {
      name: entry.name,
      key: entry.key,
      kind: entry.kind,
      imageUrl,
      isActive: true,
      sortOrder: entry.sortOrder,
    });

    return {
      key: entry.key,
      ok: true,
      skipped: false,
      forced: Boolean(existing && force),
      imageUrl,
    };
  } catch (err) {
    if (uploadedThisRun) {
      try {
        await storageAdapter.delete(objectPath);
      } catch {
        // Best-effort only.
      }
    }
    return {
      key: entry.key,
      ok: false,
      skipped: false,
      reason: err?.message ?? String(err),
    };
  }
}

/** Seeds every entry, independently - one entry's failure never blocks another's. */
export async function runSeed(entries, { repoRoot, firestoreAdapter, storageAdapter, force }) {
  const results = [];
  for (const entry of entries) {
    results.push(
      await seedOneCategory(entry, { repoRoot, firestoreAdapter, storageAdapter, force }),
    );
  }
  return results;
}

/** Pure guard mirroring migrate_product_images/lib.mjs's assertProjectGuard. */
export function assertProjectGuard(confirmedProjectId) {
  if (confirmedProjectId !== CONFIRMED_PROJECT_ID) {
    throw new Error(
      `Refusing to run live writes: --project must be exactly "${CONFIRMED_PROJECT_ID}" ` +
        `(got ${confirmedProjectId ? `"${confirmedProjectId}"` : 'nothing'}). ` +
        'This guard exists so a copy-pasted command can never silently write to the wrong project.',
    );
  }
}
