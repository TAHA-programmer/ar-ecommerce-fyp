// TWin AR — Phase 9.2 coverage-expansion Room-AR rollout — core logic.
//
// Pure / injectable functions only (no firebase-admin here) so this module is
// unit-testable with fake Storage + Firestore adapters. The CLI
// (rollout_ar_coverage_expansion.mjs) wires it to the real Admin SDK. Mirrors
// scripts/upload_ar_models/lib.mjs's Storage-preflight pattern and
// scripts/migrate_ar_catalogue/lib.mjs's backup/rollback pattern, generalised
// from "4 sources -> 4 destinations" to "6 sources -> 26 destinations"
// (tracker §15/§16, `18_ROOM_AR_PRODUCT_COVERAGE_MATRIX.md` §18 v5).
//
// Scope: for the 26 Phase 9.2 coverage-expansion product ids ONLY —
// `velvet-armchair`, `wooden-console`, `marble-side-table`, and all 23
// `beige-ar-in-stock-{2..24}` ids — uploads each destination's GLB (one of
// six shared source designs — three groups of `beige-ar-*` ids each share one
// design, rule 9) to its own versioned Storage object, then writes that
// product's `ar*` Firestore fields, ONE PRODUCT AT A TIME, each in its own
// transaction (products are independent; there is no cross-product invariant
// to protect the way the original four's title/spec/gallery recast needed
// one shared transaction). Never touches the original four products, never
// touches any field other than the `ar*` block, never creates a Firestore
// document, never overwrites a destination that already holds different
// bytes or a different `ar*` contract — that always BLOCKS instead.
//
// Idempotent: re-running after a partial success only acts on the entries
// still `pending`; everything already correct is reported `identical` and
// skipped.

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

export const CONFIRMED_PROJECT_ID = 'twin-ar-d4d75';
export const BACKUP_SCHEMA_VERSION = 'ar-coverage-expansion-rollout/1';

// Matches storage.rules' 12 MB transport ceiling.
export const MAX_TRANSPORT_BYTES = 12 * 1024 * 1024;
// Matches SCALE_CONTRACT.md / the Admin app's own authoring budget
// (`kArModelMaxUploadBytes`) — every genuinely new upload should fit this,
// the 12 MB figure above is only the hard outer limit.
export const MAX_AUTHORING_BYTES = 8 * 1024 * 1024;

export const AR_MODEL_CONTENT_TYPE = 'model/gltf-binary';
export const AR_MODEL_CACHE_CONTROL = 'public, max-age=31536000, immutable';
export const SCALE_CONTRACT = 'twin-ar/scale-contract-9.2.2';

/**
 * The six developer-approved, supervisor-approved source designs (tracker
 * §15/§16; hashes/dims cross-verified in `_ar_assets/candidates/PROVENANCE.md`
 * and already registered in `RoomArProductManifest`/`kRoomArProductMetadata`).
 * Each group's `destinationIds` is exactly the set of product ids that share
 * that one design (rule 9 — a shared design still means N separate Storage
 * uploads + N separate Firestore writes, one per listing).
 */
export const SOURCE_GROUPS = [
  {
    group: 'velvet-armchair',
    sourceRelPath: '_ar_assets/candidates/velvet_armchair_chatgpt_original.glb',
    expectedSha256:
      '9909929fdc84adf526127887ab782805bee0ff6863c04e0dd1510a4264f8a09e',
    widthM: 0.72,
    depthM: 0.76,
    heightM: 0.78,
    destinationIds: ['velvet-armchair'],
  },
  {
    group: 'wooden-console',
    sourceRelPath: '_ar_assets/candidates/wooden_console_chatgpt_original.glb',
    expectedSha256:
      'b22ac85b25cac2b4924e04793701c95907c36474bb04df7c4aa9ddda51e03433',
    widthM: 1.8,
    depthM: 0.42,
    heightM: 0.72,
    destinationIds: ['wooden-console'],
  },
  {
    group: 'marble-side-table',
    sourceRelPath:
      '_ar_assets/candidates/marble_side_table_chatgpt_original.glb',
    expectedSha256:
      '287b8bb97b3bff21de651b49dbb46024be0462fc2ea3e49c6a08964f79b9b7b3',
    widthM: 0.46,
    depthM: 0.46,
    heightM: 0.53,
    destinationIds: ['marble-side-table'],
  },
  {
    group: 'beige-ar-rug',
    sourceRelPath: '_ar_assets/candidates/beige_ar_rug_chatgpt_original.glb',
    expectedSha256:
      'd21f1adaf04708ff96976282fa7543814c9718028a3297fe392b0847766837e5',
    widthM: 2.0,
    depthM: 1.35,
    heightM: 0.012,
    destinationIds: [
      'beige-ar-in-stock-5',
      'beige-ar-in-stock-7',
      'beige-ar-in-stock-11',
      'beige-ar-in-stock-13',
      'beige-ar-in-stock-17',
      'beige-ar-in-stock-19',
      'beige-ar-in-stock-23',
    ],
  },
  {
    group: 'beige-ar-sofa',
    sourceRelPath: '_ar_assets/candidates/beige_ar_sofa_chatgpt_original.glb',
    expectedSha256:
      '5dfc2a86ea7a9c66ca4190179a31e1d2f2b28c9829cbd9b2240b9284c7db2a84',
    widthM: 2.5,
    depthM: 1.6,
    heightM: 0.7,
    destinationIds: [
      'beige-ar-in-stock-2',
      'beige-ar-in-stock-4',
      'beige-ar-in-stock-8',
      'beige-ar-in-stock-10',
      'beige-ar-in-stock-14',
      'beige-ar-in-stock-16',
      'beige-ar-in-stock-20',
      'beige-ar-in-stock-22',
    ],
  },
  {
    group: 'beige-ar-vase',
    sourceRelPath: '_ar_assets/candidates/beige_ar_vase_chatgpt_original.glb',
    expectedSha256:
      'cf8c32bab30e43ca138fd07b5aca50a792389d91228aaacb05cb09321989295d',
    widthM: 0.15,
    depthM: 0.15,
    heightM: 0.2,
    destinationIds: [
      'beige-ar-in-stock-3',
      'beige-ar-in-stock-6',
      'beige-ar-in-stock-9',
      'beige-ar-in-stock-12',
      'beige-ar-in-stock-15',
      'beige-ar-in-stock-18',
      'beige-ar-in-stock-21',
      'beige-ar-in-stock-24',
    ],
  },
];

export const ALL_DESTINATION_IDS = SOURCE_GROUPS.flatMap(
  (g) => g.destinationIds,
);

export function assertProjectGuard(mode, confirmedProjectId) {
  if (mode !== 'apply' && mode !== 'rollback-apply') return;
  if (confirmedProjectId !== CONFIRMED_PROJECT_ID) {
    throw new Error(
      `Refusing to run live writes: --project must be exactly ` +
        `"${CONFIRMED_PROJECT_ID}" (got ${
          confirmedProjectId ? `"${confirmedProjectId}"` : 'nothing'
        }).`,
    );
  }
}

/** Extra, deliberately-worded confirmation distinct from the 4-product
 *  `migrate_ar_catalogue --dimensions-approved` flag, so the two tools can
 *  never be invoked with a copy-pasted, wrong set of flags. */
export function assertExpansionConfirmed(mode, confirmed) {
  if (mode !== 'apply') return;
  if (!confirmed) {
    throw new Error(
      'Refusing to run live writes: pass --confirm-expansion-rollout — this ' +
        'authorizes writing Storage objects + `ar*` Firestore fields for the ' +
        '26 Phase 9.2 coverage-expansion product ids (never the original four).',
    );
  }
}

export function sha256Hex(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

export function md5Base64(buffer) {
  return createHash('md5').update(buffer).digest('base64');
}

export function storagePathFor(productId) {
  return `products/${productId}/ar/model-v1.glb`;
}

/** `ar*` Firestore fields this rollout writes for one destination id. */
export function arFieldsForDestination(productId, group, sha256) {
  return {
    arModelStoragePath: storagePathFor(productId),
    arModelFormat: 'glb',
    arModelVersion: '1',
    arModelSha256: sha256,
    arWidthM: group.widthM,
    arDepthM: group.depthM,
    arHeightM: group.heightM,
    arScale: 1.0,
    arScaleContract: SCALE_CONTRACT,
  };
}

/** Reads + validates one group's source file. Never throws. */
export function preflightSource(workspaceRoot, group) {
  const abs = path.join(workspaceRoot, group.sourceRelPath);
  if (!existsSync(abs)) {
    return { ok: false, reason: `source file not found: ${group.sourceRelPath}` };
  }
  const stat = statSync(abs);
  if (!stat.isFile()) {
    return { ok: false, reason: `source is not a file: ${group.sourceRelPath}` };
  }
  if (stat.size === 0) {
    return { ok: false, reason: `source file is empty: ${group.sourceRelPath}` };
  }
  if (stat.size > MAX_AUTHORING_BYTES) {
    return {
      ok: false,
      reason:
        `source file is ${stat.size} bytes, over the ${MAX_AUTHORING_BYTES}-byte ` +
        'authoring budget (SCALE_CONTRACT.md / kArModelMaxUploadBytes)',
    };
  }
  const buffer = readFileSync(abs);
  if (
    buffer.length < 12 ||
    buffer[0] !== 0x67 ||
    buffer[1] !== 0x6c ||
    buffer[2] !== 0x54 ||
    buffer[3] !== 0x46
  ) {
    return { ok: false, reason: 'source file is not a GLB (bad magic bytes)' };
  }
  const sha = sha256Hex(buffer);
  if (sha !== group.expectedSha256) {
    return {
      ok: false,
      reason:
        `source SHA-256 mismatch for group "${group.group}": expected ` +
        `${group.expectedSha256}, got ${sha}`,
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

/** Classify one destination's current Storage object against the verified
 *  source. `absent` | `identical` | `conflict` — a `conflict` always blocks. */
export async function preflightStorageDestination(storageAdapter, productId, source) {
  const destPath = storagePathFor(productId);
  const meta = await storageAdapter.getMetadata(destPath);
  if (!meta || !meta.exists) return { state: 'absent', destPath, detail: null };

  const mismatches = [];
  if ((meta.md5Base64 ?? null) !== source.md5) mismatches.push('md5 mismatch');
  if (Number(meta.size ?? -1) !== source.sizeBytes) mismatches.push('size mismatch');
  if ((meta.metadata?.twinArArModelSha256 ?? null) !== source.sha256) {
    mismatches.push('twinArArModelSha256 mismatch or missing');
  }
  if (mismatches.length > 0) {
    return { state: 'conflict', destPath, detail: mismatches.join('; ') };
  }
  return { state: 'identical', destPath, detail: `generation ${meta.generation ?? '?'}` };
}

/** Classify one destination's current Firestore document against the target
 *  `ar*` fields. `absent` (no ar* yet, safe to write) | `identical` (already
 *  exactly this rollout's target — skip) | `conflict` (doc missing / wrong
 *  type / not customer-eligible / already carries a DIFFERENT `ar*` contract
 *  — never silently overwritten) . */
export async function preflightFirestoreDestination(
  firestoreAdapter,
  productId,
  target,
) {
  const doc = await firestoreAdapter.getProduct(productId);
  if (!doc || !doc.data) {
    return { state: 'conflict', detail: `no Firestore document for ${productId}` };
  }
  const data = doc.data;
  if (data.experienceType !== 'roomAr') {
    return {
      state: 'conflict',
      detail: `experienceType is "${data.experienceType}", not "roomAr"`,
    };
  }
  const existingPath = data.arModelStoragePath;
  if (existingPath == null || existingPath === '') {
    return { state: 'absent', detail: null, updateTime: doc.updateTime };
  }
  const keys = Object.keys(target);
  const mismatches = keys.filter((k) => data[k] !== target[k]);
  if (mismatches.length === 0) {
    return { state: 'identical', detail: null, updateTime: doc.updateTime };
  }
  return {
    state: 'conflict',
    detail:
      `document already carries a different ar* contract (mismatched: ` +
      `${mismatches.join(', ')}) — never overwritten by this tool`,
    updateTime: doc.updateTime,
  };
}

/**
 * Full plan across all 26 destinations. `abort` is set if ANY entry has a
 * blocking problem (source, Storage, or Firestore) — the whole rollout
 * refuses to write anything rather than applying a partial, confusing state.
 */
export async function buildRolloutPlan(storageAdapter, firestoreAdapter, workspaceRoot) {
  const entries = [];
  const problems = [];

  for (const group of SOURCE_GROUPS) {
    const source = preflightSource(workspaceRoot, group);
    for (const productId of group.destinationIds) {
      if (!source.ok) {
        problems.push({ productId, reason: source.reason });
        entries.push({ productId, group: group.group, source, storage: null, firestore: null });
        continue;
      }
      const storage = await preflightStorageDestination(storageAdapter, productId, source);
      if (storage.state === 'conflict') {
        problems.push({
          productId,
          reason: `Storage ${storage.destPath} conflicts: ${storage.detail}`,
        });
      }
      const target = arFieldsForDestination(productId, group, source.sha256);
      const firestore = await preflightFirestoreDestination(
        firestoreAdapter,
        productId,
        target,
      );
      if (firestore.state === 'conflict') {
        problems.push({ productId, reason: `Firestore: ${firestore.detail}` });
      }
      entries.push({ productId, group: group.group, source, storage, firestore, target });
    }
  }

  const ready = entries.filter(
    (e) =>
      e.source.ok &&
      e.storage?.state !== 'conflict' &&
      e.firestore?.state !== 'conflict' &&
      !(e.storage?.state === 'identical' && e.firestore?.state === 'identical'),
  );
  const alreadyDone = entries.filter(
    (e) => e.storage?.state === 'identical' && e.firestore?.state === 'identical',
  );

  return {
    entries,
    problems,
    abort: problems.length > 0,
    readyCount: ready.length,
    alreadyDoneCount: alreadyDone.length,
  };
}

export function summarizePlan(plan) {
  const lines = [];
  lines.push('--- Phase 9.2 coverage-expansion Room-AR rollout: DRY RUN ---');
  for (const e of plan.entries) {
    if (!e.source.ok) {
      lines.push(`  BLOCK  ${e.productId} [${e.group}]: ${e.source.reason}`);
      continue;
    }
    if (e.storage.state === 'identical' && e.firestore.state === 'identical') {
      lines.push(`  SKIP   ${e.productId} [${e.group}] (already fully rolled out)`);
      continue;
    }
    if (e.storage.state === 'conflict') {
      lines.push(`  BLOCK  ${e.productId} [${e.group}]: Storage ${e.storage.detail}`);
      continue;
    }
    if (e.firestore.state === 'conflict') {
      lines.push(`  BLOCK  ${e.productId} [${e.group}]: Firestore ${e.firestore.detail}`);
      continue;
    }
    const storageAction = e.storage.state === 'absent' ? 'upload' : 'storage-ok';
    const firestoreAction = e.firestore.state === 'absent' ? 'write ar*' : 'firestore-ok';
    lines.push(`  READY  ${e.productId} [${e.group}]: ${storageAction} + ${firestoreAction}`);
  }
  lines.push('');
  lines.push(
    `Ready: ${plan.readyCount}   already rolled out: ${plan.alreadyDoneCount}   ` +
      `blocked: ${plan.problems.length}`,
  );
  if (plan.abort) {
    lines.push('');
    lines.push('RUN BLOCKED — fix the problems above; nothing will be written:');
    for (const p of plan.problems) lines.push(`  - [${p.productId}] ${p.reason}`);
  }
  return lines;
}

/** The custom metadata written on every uploaded Storage object. */
export function objectMetadataFor(group, sha256) {
  return {
    twinArArModelSha256: sha256,
    twinArArModelVersion: '1',
    twinArArWidthM: String(group.widthM),
    twinArArDepthM: String(group.depthM),
    twinArArHeightM: String(group.heightM),
    twinArArScaleContract: SCALE_CONTRACT,
  };
}

/**
 * Applies every `ready` entry ONE PRODUCT AT A TIME: create-only Storage
 * upload (skipped if already `identical`), then — only once the upload
 * genuinely succeeded or was already correct — a single-document Firestore
 * transaction that re-checks the document is still in its preflighted state
 * before writing (rejects on drift rather than clobbering). A failure on one
 * product never touches another. Returns a report + a backup payload for
 * rollback.
 */
export async function applyRollout(plan, storageAdapter, firestoreAdapter) {
  if (plan.abort) throw new Error('applyRollout called on an aborting plan');

  const groupsByName = Object.fromEntries(SOURCE_GROUPS.map((g) => [g.group, g]));
  const uploaded = [];
  const written = [];
  const skipped = [];
  const failed = [];
  const backupEntries = [];

  for (const e of plan.entries) {
    if (e.storage.state === 'identical' && e.firestore.state === 'identical') {
      skipped.push({ productId: e.productId });
      continue;
    }
    const group = groupsByName[e.group];
    try {
      if (e.storage.state === 'absent') {
        const result = await storageAdapter.upload(e.storage.destPath, e.source.buffer, {
          contentType: AR_MODEL_CONTENT_TYPE,
          cacheControl: AR_MODEL_CACHE_CONTROL,
          metadata: objectMetadataFor(group, e.source.sha256),
          ifGenerationMatch: 0,
        });
        uploaded.push({
          productId: e.productId,
          destPath: e.storage.destPath,
          generation: result?.generation ?? null,
        });
      }

      if (e.firestore.state === 'absent') {
        backupEntries.push({
          productId: e.productId,
          preUpdateTime: e.firestore.updateTime,
          writtenKeys: Object.keys(e.target),
        });
        await firestoreAdapter.writeArFieldsIfUnchanged(
          e.productId,
          e.target,
          e.firestore.updateTime,
        );
        written.push({ productId: e.productId, fields: e.target });
      }
    } catch (err) {
      failed.push({ productId: e.productId, error: err?.message ?? String(err) });
    }
  }

  return {
    ranAt: new Date().toISOString(),
    projectId: CONFIRMED_PROJECT_ID,
    uploaded,
    written,
    skipped,
    failed,
    backup: {
      schemaVersion: BACKUP_SCHEMA_VERSION,
      createdAt: new Date().toISOString(),
      entries: backupEntries,
    },
  };
}

/** Restores exactly the `ar*` fields this rollout wrote, one product at a
 *  time, ONLY for a document still in its exact just-written state (its
 *  `arModelStoragePath` still matches what was written, i.e. nothing else
 *  has touched it since). A product that drifted is skipped with a reason,
 *  never force-restored. */
export async function applyRollback(backup, firestoreAdapter) {
  if (backup.schemaVersion !== BACKUP_SCHEMA_VERSION) {
    throw new Error(
      `backup schemaVersion mismatch: expected ${BACKUP_SCHEMA_VERSION}, got ${backup.schemaVersion}`,
    );
  }
  const restored = [];
  const skipped = [];
  for (const entry of backup.entries ?? []) {
    try {
      await firestoreAdapter.deleteArFieldsIfWrittenByUs(
        entry.productId,
        entry.writtenKeys,
      );
      restored.push({ productId: entry.productId });
    } catch (err) {
      skipped.push({ productId: entry.productId, reason: err?.message ?? String(err) });
    }
  }
  return { restored, skipped };
}
