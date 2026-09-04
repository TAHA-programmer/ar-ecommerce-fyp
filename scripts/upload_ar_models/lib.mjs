// TWin AR — Phase 9.2 R10: Room-AR GLB upload tool — core logic.
//
// Pure / injectable functions only (no direct firebase-admin here) so this
// module is unit-testable with a fake Storage adapter. The CLI
// (upload_ar_models.mjs) wires it to the real Admin SDK. Mirrors
// scripts/migrate_product_images/lib.mjs's structure and its
// assertProjectGuard pattern.
//
// Scope: uploads exactly the four physically-approved Room-AR GLBs to their
// versioned Storage object paths and NOTHING else. Never writes Firestore,
// never deletes a Storage object, never runs the seed script. Idempotent:
// a destination that already holds the exact expected bytes + metadata is
// skipped; a destination that holds *different* bytes/metadata blocks the
// whole run rather than being overwritten.

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

export const CONFIRMED_PROJECT_ID = 'twin-ar-d4d75';

/// Matches storage.rules and RoomArModelService.defaultMaxDownloadBytes.
export const MAX_AR_MODEL_BYTES = 12 * 1024 * 1024;

export const AR_MODEL_CONTENT_TYPE = 'model/gltf-binary';

/// Versioned object path → safe to mark immutable for a year.
export const AR_MODEL_CACHE_CONTROL = 'public, max-age=31536000, immutable';

/**
 * The exact four-item allowlist. Every field is checked before anything is
 * uploaded:
 *  - `sourceRelPath` — canonical local GLB, relative to the workspace root
 *    (`C:\dev\Project_P2`), i.e. the `_ar_assets` sibling of `twin_ar`;
 *  - `destPath` — the Storage object path, identical to
 *    `RoomArProductManifest.storagePathFor(productId)` / tracker §2.10;
 *  - `expectedSha256` — the independently-verified hash from tracker §2.4–2.8;
 *  - `version` + `widthM`/`depthM`/`heightM` — echoed into the object's custom
 *    metadata so a later reader (or this tool, re-run) can prove provenance;
 *  - `contentType` / `cacheControl` — what `storage.rules` accepts and what
 *    `RoomArModelService` expects.
 */
export const AR_MODEL_ALLOWLIST = [
  {
    productId: 'luna-accent-chair',
    sourceRelPath: '_ar_assets/candidates/luna_chair_chatgpt_v3_normalized.glb',
    destPath: 'products/luna-accent-chair/ar/model-v1.glb',
    expectedSha256:
      'd67c68f823d06881ec1aabf7f8ca6f0128f1016483ea0307f5c2ecef66b3cf94',
    version: '1',
    widthM: 0.7,
    depthM: 0.72,
    heightM: 0.82,
    contentType: AR_MODEL_CONTENT_TYPE,
    cacheControl: AR_MODEL_CACHE_CONTROL,
  },
  {
    productId: 'glass-coffee-table',
    sourceRelPath:
      '_ar_assets/candidates/coffee_table_chatgpt_v1_normalized.glb',
    destPath: 'products/glass-coffee-table/ar/model-v1.glb',
    expectedSha256:
      'd10f32a7373d84031d3e51b8e9770610f514f62fa56110608852f1640ab7a727',
    version: '1',
    widthM: 0.9,
    depthM: 0.9,
    heightM: 0.42,
    contentType: AR_MODEL_CONTENT_TYPE,
    cacheControl: AR_MODEL_CACHE_CONTROL,
  },
  {
    productId: 'modern-table-lamp',
    sourceRelPath: '_ar_assets/candidates/lamp_chatgpt_v1_normalized.glb',
    destPath: 'products/modern-table-lamp/ar/model-v1.glb',
    expectedSha256:
      'ee417ead58e72de9518358288f089bad272779c190125e01ac372fcfc16bb565',
    version: '1',
    widthM: 0.2,
    depthM: 0.2,
    heightM: 0.45,
    contentType: AR_MODEL_CONTENT_TYPE,
    cacheControl: AR_MODEL_CACHE_CONTROL,
  },
  {
    productId: 'luna-3-seater-sofa',
    sourceRelPath: '_ar_assets/candidates/sofa_chatgpt_v1_normalized.glb',
    destPath: 'products/luna-3-seater-sofa/ar/model-v1.glb',
    expectedSha256:
      'efd400046b265fd49d8d2b0382d378d230d625cb879740a3ef0697ca86c0d187',
    version: '1',
    widthM: 2.65,
    depthM: 1.65,
    heightM: 0.82,
    contentType: AR_MODEL_CONTENT_TYPE,
    cacheControl: AR_MODEL_CACHE_CONTROL,
  },
];

/**
 * Refuse a live run unless `--project` is exactly the confirmed project id —
 * so a copy-pasted command can never write to the wrong project. Identical
 * contract to `scripts/migrate_product_images/lib.mjs`.
 */
export function assertProjectGuard(mode, confirmedProjectId) {
  if (mode !== 'apply') return;
  if (confirmedProjectId !== CONFIRMED_PROJECT_ID) {
    throw new Error(
      `Refusing to run live uploads: --project must be exactly ` +
        `"${CONFIRMED_PROJECT_ID}" (got ${
          confirmedProjectId ? `"${confirmedProjectId}"` : 'nothing'
        }).`,
    );
  }
}

export function sha256Hex(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

export function md5Base64(buffer) {
  return createHash('md5').update(buffer).digest('base64');
}

/**
 * Reads + validates one allowlist item's source file. Never throws.
 * `{ ok: true, buffer, sizeBytes, sha256, md5 }` or `{ ok: false, reason }`.
 */
export function preflightSource(workspaceRoot, item) {
  const abs = path.join(workspaceRoot, item.sourceRelPath);
  if (!existsSync(abs)) {
    return { ok: false, reason: `source file not found: ${item.sourceRelPath}` };
  }
  const stat = statSync(abs);
  if (!stat.isFile()) {
    return { ok: false, reason: `source is not a file: ${item.sourceRelPath}` };
  }
  if (stat.size === 0) {
    return { ok: false, reason: `source file is empty: ${item.sourceRelPath}` };
  }
  if (stat.size > MAX_AR_MODEL_BYTES) {
    return {
      ok: false,
      reason: `source file is ${stat.size} bytes, over the ${MAX_AR_MODEL_BYTES} limit`,
    };
  }
  const buffer = readFileSync(abs);
  // Light GLB sanity — full structural verification is RoomArModelService's job
  // at load time; here we only guard against an obviously-wrong file.
  if (
    buffer.length < 12 ||
    buffer[0] !== 0x67 ||
    buffer[1] !== 0x6c ||
    buffer[2] !== 0x54 ||
    buffer[3] !== 0x46
  ) {
    return { ok: false, reason: `source file is not a GLB (bad magic bytes)` };
  }
  const sha = sha256Hex(buffer);
  if (sha !== item.expectedSha256) {
    return {
      ok: false,
      reason:
        `source SHA-256 mismatch for ${item.productId}: ` +
        `expected ${item.expectedSha256}, got ${sha}`,
    };
  }
  return {
    ok: true,
    buffer,
    sizeBytes: stat.size,
    sha256: sha,
    md5: md5Base64(buffer),
  };
}

/** The custom metadata written alongside every uploaded object. */
export function objectMetadataFor(item, sha256) {
  return {
    twinArArModelSha256: sha256,
    twinArArModelVersion: String(item.version),
    twinArArWidthM: String(item.widthM),
    twinArArDepthM: String(item.depthM),
    twinArArHeightM: String(item.heightM),
    twinArArScaleContract: 'twin-ar/scale-contract-9.2.2',
  };
}

/**
 * Every field that must be present AND exactly equal for an existing
 * destination object to count as `identical` (and be safely skipped). A
 * missing OR differing value in ANY of these is a `conflict` — the run then
 * aborts entirely and the object is never overwritten, repaired, deleted or
 * partially uploaded.
 */
export function requiredDestinationFields(item, source) {
  return {
    md5Base64: source.md5,
    size: source.sizeBytes,
    contentType: item.contentType,
    cacheControl: item.cacheControl,
    ...objectMetadataFor(item, source.sha256), // the six twinArAr* fields
  };
}

/**
 * Classifies the destination for one item against the verified source.
 * Returns `{ state, detail }` with state one of:
 *  - `absent`     — nothing there; safe to create;
 *  - `identical`  — already holds the exact bytes AND every required metadata
 *                   field, all present and exactly equal; skip;
 *  - `conflict`   — anything else (different bytes/size/type/cache-control, or
 *                   ANY missing/differing provenance field). The run must abort
 *                   — never overwrite.
 */
export async function preflightDestination(storageAdapter, item, source) {
  const meta = await storageAdapter.getMetadata(item.destPath);
  if (!meta || !meta.exists) return { state: 'absent', detail: null };

  const required = requiredDestinationFields(item, source);
  const actual = {
    md5Base64: meta.md5Base64 ?? null,
    size: meta.size != null ? Number(meta.size) : null,
    contentType: meta.contentType ?? null,
    cacheControl: meta.cacheControl ?? null,
    twinArArModelSha256: meta.metadata?.twinArArModelSha256 ?? null,
    twinArArModelVersion: meta.metadata?.twinArArModelVersion ?? null,
    twinArArWidthM: meta.metadata?.twinArArWidthM ?? null,
    twinArArDepthM: meta.metadata?.twinArArDepthM ?? null,
    twinArArHeightM: meta.metadata?.twinArArHeightM ?? null,
    twinArArScaleContract: meta.metadata?.twinArArScaleContract ?? null,
  };

  const mismatches = [];
  for (const [key, want] of Object.entries(required)) {
    const got = actual[key];
    if (got == null) {
      mismatches.push(`${key} missing on the existing object`);
    } else if (key === 'size') {
      if (Number(got) !== Number(want)) {
        mismatches.push(`size ${got} != ${want}`);
      }
    } else if (String(got) !== String(want)) {
      mismatches.push(`${key} ${got} != ${want}`);
    }
  }

  if (mismatches.length > 0) {
    return { state: 'conflict', detail: mismatches.join('; ') };
  }
  return { state: 'identical', detail: `generation ${meta.generation ?? '?'}` };
}

/**
 * Full plan: preflight every source, then every destination. If ANY source
 * is missing/mismatched OR any destination conflicts, `abort` is set and no
 * upload should happen.
 */
export async function buildUploadPlan(storageAdapter, workspaceRoot) {
  const entries = [];
  const problems = [];

  for (const item of AR_MODEL_ALLOWLIST) {
    const source = preflightSource(workspaceRoot, item);
    if (!source.ok) {
      problems.push({ productId: item.productId, reason: source.reason });
      entries.push({ item, source, destination: null });
      continue;
    }
    const destination = await preflightDestination(storageAdapter, item, source);
    if (destination.state === 'conflict') {
      problems.push({
        productId: item.productId,
        reason: `destination ${item.destPath} conflicts: ${destination.detail}`,
      });
    }
    entries.push({ item, source, destination });
  }

  const toCreate = entries.filter(
    (e) => e.source.ok && e.destination?.state === 'absent',
  );
  const toSkip = entries.filter((e) => e.destination?.state === 'identical');

  return {
    entries,
    problems,
    abort: problems.length > 0,
    toCreateCount: toCreate.length,
    toSkipCount: toSkip.length,
  };
}

/**
 * Uploads every `absent` entry with an `ifGenerationMatch: 0` precondition
 * (create-only — a race that created the object first makes this fail rather
 * than clobber). Never touches `identical`/`conflict` entries, never deletes.
 * Returns a machine-readable report + a rollback inventory (the objects this
 * run created, which a developer can delete manually if needed).
 */
export async function applyUpload(plan, storageAdapter) {
  if (plan.abort) {
    throw new Error('applyUpload called on an aborting plan');
  }
  const created = [];
  const skipped = [];
  const failed = [];

  for (const entry of plan.entries) {
    const { item, source, destination } = entry;
    if (destination.state === 'identical') {
      skipped.push({ productId: item.productId, destPath: item.destPath });
      continue;
    }
    if (destination.state !== 'absent') continue;
    try {
      const result = await storageAdapter.upload(item.destPath, source.buffer, {
        contentType: item.contentType,
        cacheControl: item.cacheControl,
        metadata: objectMetadataFor(item, source.sha256),
        ifGenerationMatch: 0,
      });
      created.push({
        productId: item.productId,
        destPath: item.destPath,
        sha256: source.sha256,
        sizeBytes: source.sizeBytes,
        generation: result?.generation ?? null,
      });
    } catch (err) {
      failed.push({
        productId: item.productId,
        destPath: item.destPath,
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
      destPath: c.destPath,
      generation: c.generation,
      note: 'created by this run — delete manually only if rolling back',
    })),
  };
}

/** Human-readable dry-run summary lines. */
export function summarizePlan(plan) {
  const lines = [];
  lines.push('--- Phase 9.2 R10 — Room-AR GLB upload: DRY RUN ---');
  for (const entry of plan.entries) {
    const { item, source, destination } = entry;
    if (!source.ok) {
      lines.push(`  BLOCK ${item.productId}: ${source.reason}`);
      continue;
    }
    const where = `${item.destPath}`;
    switch (destination.state) {
      case 'absent':
        lines.push(
          `  UPLOAD ${item.productId} -> ${where} ` +
            `(${source.sizeBytes} bytes, sha ${source.sha256.slice(0, 12)}…)`,
        );
        break;
      case 'identical':
        lines.push(`  SKIP   ${item.productId} -> ${where} (already correct)`);
        break;
      case 'conflict':
        lines.push(
          `  BLOCK  ${item.productId} -> ${where}: ${destination.detail}`,
        );
        break;
    }
  }
  lines.push('');
  lines.push(`Would upload: ${plan.toCreateCount}   skip: ${plan.toSkipCount}`);
  if (plan.abort) {
    lines.push('');
    lines.push('RUN BLOCKED — fix the problems above; no upload will happen:');
    for (const p of plan.problems) lines.push(`  - [${p.productId}] ${p.reason}`);
  }
  return lines;
}
