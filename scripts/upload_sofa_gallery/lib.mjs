// TWin AR — Phase 9.2 R14 Stage A: sofa customer-gallery uploader — core logic.
//
// Pure / injectable (no firebase-admin here). Uploads the six approved
// Luna Right-Chaise Sectional Sofa studio renders to their deterministic
// `products/luna-3-seater-sofa/images/img-<sha16>.png` Storage paths.
//
// Stage A ONLY touches Storage — never Firestore, never the customer
// catalogue. The catalogue recast (Stage B, ../migrate_ar_catalogue/) is
// what makes these renders customer-visible, and only after it independently
// re-verifies every object exists and matches.
//
// Idempotent: an object already present with byte-identical content (md5 +
// size) is skipped. An object present with DIFFERENT bytes blocks the whole
// run — never overwritten.

import {
  CONFIRMED_PROJECT_ID,
  SOFA_GALLERY,
  SOFA_IMAGE_CONTENT_TYPE,
  SOFA_SHA256_METADATA_KEY,
  objectPathFor,
  preflightSource,
} from './sofa_gallery.mjs';

export { CONFIRMED_PROJECT_ID };

export const AR_MODEL_IMAGE_CONTENT_TYPE = SOFA_IMAGE_CONTENT_TYPE;

export function assertProjectGuard(mode, confirmedProjectId) {
  if (mode !== 'apply') return;
  if (confirmedProjectId !== CONFIRMED_PROJECT_ID) {
    throw new Error(
      `Refusing to run live uploads: --project must be exactly "${CONFIRMED_PROJECT_ID}" ` +
        `(got ${confirmedProjectId ? `"${confirmedProjectId}"` : 'nothing'}).`,
    );
  }
}

/**
 * Classifies one already-verified source against the live Storage object.
 * `absent` (create), `identical` (skip), `conflict` (abort the run).
 *
 * "identical" requires the bytes (md5 + size) AND the exact content type AND
 * the required `twinArSofaGallerySha256` custom metadata to all match — an
 * object whose bytes match but whose metadata is missing/wrong is a `conflict`
 * (the Stage-B recast is gated on that metadata), and this run neither skips
 * nor overwrites it.
 */
export async function preflightDestination(storageAdapter, item, source) {
  const meta = await storageAdapter.getMetadata(objectPathFor(item));
  if (!meta || !meta.exists) return { state: 'absent', detail: null };

  const mismatches = [];
  const bytesMatch =
    meta.md5Base64 != null &&
    meta.md5Base64 === source.md5 &&
    meta.size != null &&
    Number(meta.size) === source.sizeBytes;

  if (meta.md5Base64 == null) mismatches.push('existing object reports no md5');
  else if (meta.md5Base64 !== source.md5) mismatches.push('bytes (md5) differ');
  if (meta.size == null) mismatches.push('existing object reports no size');
  else if (Number(meta.size) !== source.sizeBytes) {
    mismatches.push(`size ${meta.size} != ${source.sizeBytes}`);
  }
  if (meta.contentType == null) {
    mismatches.push('existing object reports no content type');
  } else if (meta.contentType !== AR_MODEL_IMAGE_CONTENT_TYPE) {
    mismatches.push(`contentType ${meta.contentType} != ${AR_MODEL_IMAGE_CONTENT_TYPE}`);
  }
  if (meta.sha256Meta == null) {
    mismatches.push(`missing required ${SOFA_SHA256_METADATA_KEY} custom metadata`);
  } else if (meta.sha256Meta !== source.sha256) {
    mismatches.push(
      `${SOFA_SHA256_METADATA_KEY} ${meta.sha256Meta} != ${source.sha256}`,
    );
  }

  if (mismatches.length > 0) {
    const note = bytesMatch
      ? ' — bytes are already identical, so this run will NOT overwrite it; ' +
        'fix the metadata in the console (or delete the object) and re-run'
      : '';
    return { state: 'conflict', detail: mismatches.join('; ') + note };
  }
  return { state: 'identical', detail: `generation ${meta.generation ?? '?'}` };
}

/** Full plan: preflight every render + every destination. No writes. */
export async function buildUploadPlan(storageAdapter, workspaceRoot) {
  const entries = [];
  const problems = [];
  for (const item of SOFA_GALLERY) {
    const source = preflightSource(workspaceRoot, item);
    if (!source.ok) {
      problems.push({ stableName: item.stableName, reason: source.reason });
      entries.push({ item, source, destination: null });
      continue;
    }
    const destination = await preflightDestination(storageAdapter, item, source);
    if (destination.state === 'conflict') {
      problems.push({
        stableName: item.stableName,
        reason: `destination ${objectPathFor(item)} conflicts: ${destination.detail}`,
      });
    }
    entries.push({ item, source, destination });
  }
  const toCreate = entries.filter((e) => e.destination?.state === 'absent');
  const toSkip = entries.filter((e) => e.destination?.state === 'identical');
  return {
    entries,
    problems,
    abort: problems.length > 0,
    toCreateCount: toCreate.length,
    toSkipCount: toSkip.length,
  };
}

/** Uploads every `absent` entry, create-only. Never overwrites, never deletes. */
export async function applyUpload(plan, storageAdapter) {
  if (plan.abort) throw new Error('applyUpload called on an aborting plan');
  const created = [];
  const skipped = [];
  const failed = [];
  for (const { item, source, destination } of plan.entries) {
    if (destination.state === 'identical') {
      skipped.push({ stableName: item.stableName, objectPath: objectPathFor(item) });
      continue;
    }
    if (destination.state !== 'absent') continue;
    try {
      const result = await storageAdapter.upload(objectPathFor(item), source.buffer, {
        contentType: AR_MODEL_IMAGE_CONTENT_TYPE,
        ifGenerationMatch: 0,
        metadata: {
          twinArSofaGalleryRole: item.role,
          twinArSofaGalleryOrder: String(item.order),
          twinArSofaGallerySha256: source.sha256,
        },
      });
      created.push({
        stableName: item.stableName,
        objectPath: objectPathFor(item),
        sha256: source.sha256,
        sizeBytes: source.sizeBytes,
        generation: result?.generation ?? null,
      });
    } catch (err) {
      failed.push({
        stableName: item.stableName,
        objectPath: objectPathFor(item),
        error: err?.message ?? String(err),
      });
    }
  }
  return {
    ranAt: new Date().toISOString(),
    projectId: CONFIRMED_PROJECT_ID,
    created,
    skipped,
    failed,
    rollbackInventory: created.map((c) => ({
      objectPath: c.objectPath,
      generation: c.generation,
      note: 'created by this run — delete manually only if rolling back',
    })),
  };
}

export function summarizePlan(plan) {
  const lines = ['--- Phase 9.2 R14 Stage A — sofa gallery upload: DRY RUN ---'];
  for (const { item, source, destination } of plan.entries) {
    if (!source.ok) {
      lines.push(`  BLOCK ${item.stableName}: ${source.reason}`);
      continue;
    }
    const where = objectPathFor(item);
    switch (destination.state) {
      case 'absent':
        lines.push(`  UPLOAD ${item.stableName} -> ${where} (${source.sizeBytes} B, sha ${source.sha256.slice(0, 12)}…)`);
        break;
      case 'identical':
        lines.push(`  SKIP   ${item.stableName} -> ${where} (already byte-identical)`);
        break;
      case 'conflict':
        lines.push(`  BLOCK  ${item.stableName} -> ${where}: ${destination.detail}`);
        break;
    }
  }
  lines.push('');
  lines.push(`Would upload: ${plan.toCreateCount}   skip: ${plan.toSkipCount}   blocked: ${plan.problems.length}`);
  if (plan.abort) {
    lines.push('\nRUN BLOCKED — fix the problems above; no upload will happen:');
    for (const p of plan.problems) lines.push(`  - [${p.stableName}] ${p.reason}`);
  }
  return lines;
}
