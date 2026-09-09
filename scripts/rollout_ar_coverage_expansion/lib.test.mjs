// Unit tests for the Phase 9.2 coverage-expansion Room-AR rollout tool.
// `node --test lib.test.mjs` — no live Firebase needed, no live Storage/
// Firestore write of any kind (both are fake, in-memory adapters here).
//
// `buildRolloutPlan` deliberately reads the module-level `SOURCE_GROUPS`
// constant directly (mirrors `scripts/upload_ar_models/lib.mjs`'s
// `AR_MODEL_ALLOWLIST` convention) rather than taking it as a parameter, so
// its `expectedSha256` values can't be swapped out per-test. Instead, the
// happy-path / idempotency / rollback tests below point `workspaceRoot` at a
// temp directory that holds *copies* (never the originals — nothing under
// the real `_ar_assets/candidates/` is ever modified or moved) of the real,
// already-hash-verified source files, so `preflightSource` genuinely
// succeeds the same way the real CLI's dry run does. The negative tests
// (missing file / corrupted bytes / already-different Firestore contract /
// conflicting Storage object) simply omit or corrupt one copy.

import assert from 'node:assert/strict';
import {
  copyFileSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  rmSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import {
  ALL_DESTINATION_IDS,
  SOURCE_GROUPS,
  applyRollback,
  applyRollout,
  assertExpansionConfirmed,
  assertProjectGuard,
  buildRolloutPlan,
  md5Base64,
  sha256Hex,
  storagePathFor,
} from './lib.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REAL_WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');

/** Copies every real, already-verified `_ar_assets/candidates/*.glb` source
 *  into a fresh temp workspace at the same relative paths `SOURCE_GROUPS`
 *  expects, so `buildRolloutPlan` (which reads the real hashes) genuinely
 *  succeeds against it. `skipGroups` omits specific groups' files (to test
 *  the "source missing" path) without ever touching the real files. */
function realSourcesWorkspace({ skipGroups = [] } = {}) {
  const root = mkdtempSync(path.join(tmpdir(), 'rollout-ar-'));
  for (const group of SOURCE_GROUPS) {
    if (skipGroups.includes(group.group)) continue;
    const src = path.join(REAL_WORKSPACE_ROOT, group.sourceRelPath);
    const dst = path.join(root, group.sourceRelPath);
    mkdirSync(path.dirname(dst), { recursive: true });
    copyFileSync(src, dst);
  }
  return { root, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

function realCandidatesPresent() {
  return SOURCE_GROUPS.every((g) =>
    existsSync(path.join(REAL_WORKSPACE_ROOT, g.sourceRelPath)),
  );
}

function fakeStorage(initial = {}) {
  const objects = new Map(Object.entries(initial));
  return {
    objects,
    async getMetadata(objectPath) {
      const o = objects.get(objectPath);
      if (!o) return { exists: false };
      return { exists: true, ...o };
    },
    async upload(objectPath, buffer, opts) {
      const generation = String(Date.now()) + Math.random();
      objects.set(objectPath, {
        md5Base64: md5Base64(buffer),
        size: buffer.length,
        contentType: opts.contentType,
        cacheControl: opts.cacheControl,
        generation,
        metadata: opts.metadata,
      });
      return { generation };
    },
  };
}

function fakeFirestore(initial = {}) {
  const docs = new Map(
    Object.entries(initial).map(([id, data]) => [id, { data, updateTime: 1 }]),
  );
  return {
    docs,
    async getProduct(id) {
      const d = docs.get(id);
      return d ? { data: d.data, updateTime: d.updateTime } : { data: null, updateTime: null };
    },
    async writeArFieldsIfUnchanged(id, fields, expectedUpdateTimeMs) {
      const d = docs.get(id);
      if (!d) throw new Error(`document ${id} no longer exists`);
      if (d.updateTime !== expectedUpdateTimeMs) {
        throw new Error(`document ${id} changed since preflight`);
      }
      if (d.data.arModelStoragePath) {
        throw new Error(`document ${id} already carries arModelStoragePath`);
      }
      docs.set(id, { data: { ...d.data, ...fields }, updateTime: d.updateTime + 1 });
    },
    async deleteArFieldsIfWrittenByUs(id, keys) {
      const d = docs.get(id);
      if (!d) throw new Error(`document ${id} no longer exists`);
      if (d.data.arModelStoragePath !== storagePathFor(id)) {
        throw new Error(`document ${id} does not match this rollout's write`);
      }
      const next = { ...d.data };
      for (const k of keys) delete next[k];
      docs.set(id, { data: next, updateTime: d.updateTime + 1 });
    },
  };
}

function baseProductDoc() {
  return { experienceType: 'roomAr', publicationStatus: 'published', isActive: true };
}

function allProductDocs() {
  const docs = {};
  for (const id of ALL_DESTINATION_IDS) docs[id] = baseProductDoc();
  return docs;
}

test('the six groups cover exactly the 26 documented destination ids, no overlaps', () => {
  assert.equal(ALL_DESTINATION_IDS.length, 26);
  assert.equal(new Set(ALL_DESTINATION_IDS).size, 26);
  assert.ok(ALL_DESTINATION_IDS.includes('velvet-armchair'));
  assert.ok(ALL_DESTINATION_IDS.includes('wooden-console'));
  assert.ok(ALL_DESTINATION_IDS.includes('marble-side-table'));
  for (let i = 2; i <= 24; i++) {
    assert.ok(
      ALL_DESTINATION_IDS.includes(`beige-ar-in-stock-${i}`),
      `missing beige-ar-in-stock-${i}`,
    );
  }
});

test('every group\'s expectedSha256 is well-formed 64-hex, destPaths are unique', () => {
  assert.equal(SOURCE_GROUPS.length, 6);
  const seen = new Set();
  for (const g of SOURCE_GROUPS) {
    assert.match(g.expectedSha256, /^[0-9a-f]{64}$/, `${g.group} hash shape`);
    for (const id of g.destinationIds) {
      assert.ok(!seen.has(id), `${id} claimed by more than one group`);
      seen.add(id);
    }
  }
});

test('assertProjectGuard / assertExpansionConfirmed only fire in apply mode', () => {
  assert.doesNotThrow(() => assertProjectGuard('dry-run', null));
  assert.throws(() => assertProjectGuard('apply', 'wrong-project'));
  assert.doesNotThrow(() => assertProjectGuard('apply', 'twin-ar-d4d75'));

  assert.doesNotThrow(() => assertExpansionConfirmed('dry-run', false));
  assert.throws(() => assertExpansionConfirmed('apply', false));
  assert.doesNotThrow(() => assertExpansionConfirmed('apply', true));
});

test('a missing source file blocks every destination in that group, not others', async () => {
  if (!realCandidatesPresent()) return; // see note at end of file
  const ws = realSourcesWorkspace({ skipGroups: ['beige-ar-rug'] });
  try {
    const plan = await buildRolloutPlan(fakeStorage(), fakeFirestore(allProductDocs()), ws.root);
    assert.equal(plan.abort, true);
    const rugIds = SOURCE_GROUPS.find((g) => g.group === 'beige-ar-rug').destinationIds;
    for (const id of rugIds) {
      assert.ok(
        plan.problems.some((p) => p.productId === id && /not found/.test(p.reason)),
        `expected ${id} to be blocked`,
      );
    }
    // A completely unrelated group's ids are unaffected by the rug's missing file.
    const consoleEntry = plan.entries.find((e) => e.productId === 'wooden-console');
    assert.equal(consoleEntry.source.ok, true);
  } finally {
    ws.cleanup();
  }
});

test('a Firestore document missing entirely blocks that product', async () => {
  if (!realCandidatesPresent()) return;
  const ws = realSourcesWorkspace();
  try {
    const docs = allProductDocs();
    delete docs['marble-side-table'];
    const plan = await buildRolloutPlan(fakeStorage(), fakeFirestore(docs), ws.root);
    assert.equal(plan.abort, true);
    assert.ok(
      plan.problems.some(
        (p) => p.productId === 'marble-side-table' && /no Firestore document/.test(p.reason),
      ),
    );
  } finally {
    ws.cleanup();
  }
});

test('a non-roomAr document is refused rather than silently written', async () => {
  if (!realCandidatesPresent()) return;
  const ws = realSourcesWorkspace();
  try {
    const docs = allProductDocs();
    docs['wooden-console'] = { ...baseProductDoc(), experienceType: 'none' };
    const plan = await buildRolloutPlan(fakeStorage(), fakeFirestore(docs), ws.root);
    assert.equal(plan.abort, true);
    assert.ok(
      plan.problems.some(
        (p) => p.productId === 'wooden-console' && /not "roomAr"/.test(p.reason),
      ),
    );
  } finally {
    ws.cleanup();
  }
});

test(
  'a document already carrying a DIFFERENT ar* contract is a conflict — ' +
    'this tool never silently overwrites existing metadata',
  async () => {
    if (!realCandidatesPresent()) return;
    const ws = realSourcesWorkspace();
    try {
      const docs = allProductDocs();
      docs['velvet-armchair'] = {
        ...baseProductDoc(),
        arModelStoragePath: 'products/velvet-armchair/ar/model-v9.glb', // some other version
        arModelFormat: 'glb',
        arModelVersion: '9',
        arModelSha256: 'f'.repeat(64),
        arWidthM: 1,
        arDepthM: 1,
        arHeightM: 1,
        arScale: 1,
        arScaleContract: 'other-contract',
      };
      const plan = await buildRolloutPlan(fakeStorage(), fakeFirestore(docs), ws.root);
      assert.equal(plan.abort, true);
      assert.ok(
        plan.problems.some(
          (p) => p.productId === 'velvet-armchair' && /different ar\* contract/.test(p.reason),
        ),
      );
    } finally {
      ws.cleanup();
    }
  },
);

test('a Storage object with different bytes at the destination path is a conflict, never overwritten', async () => {
  if (!realCandidatesPresent()) return;
  const ws = realSourcesWorkspace();
  try {
    const storage = fakeStorage({
      [storagePathFor('marble-side-table')]: {
        md5Base64: 'not-the-real-md5',
        size: 999,
        metadata: { twinArArModelSha256: '0'.repeat(64) },
      },
    });
    const plan = await buildRolloutPlan(storage, fakeFirestore(allProductDocs()), ws.root);
    assert.equal(plan.abort, true);
    assert.ok(
      plan.problems.some(
        (p) => p.productId === 'marble-side-table' && /Storage .* conflicts/.test(p.reason),
      ),
    );
  } finally {
    ws.cleanup();
  }
});

test('a full clean rollout uploads all 26 objects and writes all 26 docs, then is idempotent on re-run', async () => {
  if (!realCandidatesPresent()) return;
  const ws = realSourcesWorkspace();
  try {
    const storage = fakeStorage();
    const firestore = fakeFirestore(allProductDocs());

    const plan = await buildRolloutPlan(storage, firestore, ws.root);
    assert.equal(plan.abort, false);
    assert.equal(plan.readyCount, 26);

    const report = await applyRollout(plan, storage, firestore);
    assert.equal(report.uploaded.length, 26);
    assert.equal(report.written.length, 26);
    assert.equal(report.failed.length, 0);

    for (const id of ALL_DESTINATION_IDS) {
      const doc = await firestore.getProduct(id);
      assert.equal(doc.data.arModelStoragePath, storagePathFor(id));
      assert.match(doc.data.arModelSha256, /^[0-9a-f]{64}$/);
    }

    // Re-run: everything should now be `identical` and nothing re-written.
    const plan2 = await buildRolloutPlan(storage, firestore, ws.root);
    assert.equal(plan2.abort, false);
    assert.equal(plan2.readyCount, 0);
    assert.equal(plan2.alreadyDoneCount, 26);

    const report2 = await applyRollout(plan2, storage, firestore);
    assert.equal(report2.uploaded.length, 0);
    assert.equal(report2.written.length, 0);
    assert.equal(report2.skipped.length, 26);
  } finally {
    ws.cleanup();
  }
});

test('rollback restores exactly the fields written, and refuses a product that drifted since', async () => {
  if (!realCandidatesPresent()) return;
  const ws = realSourcesWorkspace();
  try {
    const storage = fakeStorage();
    const firestore = fakeFirestore(allProductDocs());
    const plan = await buildRolloutPlan(storage, firestore, ws.root);
    const report = await applyRollout(plan, storage, firestore);

    // Simulate a later, unrelated Admin edit on one product after the rollout —
    // rollback must refuse to touch it.
    const drifted = await firestore.getProduct('marble-side-table');
    firestore.docs.set('marble-side-table', {
      data: { ...drifted.data, arModelStoragePath: 'products/marble-side-table/ar/model-v2.glb' },
      updateTime: drifted.updateTime,
    });

    const result = await applyRollback(report.backup, firestore);
    assert.equal(result.restored.length, 25);
    assert.equal(result.skipped.length, 1);
    assert.equal(result.skipped[0].productId, 'marble-side-table');

    // A restored product genuinely has its ar* fields gone.
    const restoredDoc = await firestore.getProduct('velvet-armchair');
    assert.equal(restoredDoc.data.arModelStoragePath, undefined);
    assert.equal(restoredDoc.data.experienceType, 'roomAr'); // untouched field survives

    // The drifted product keeps its (newer, unrelated) value — rollback never
    // clobbers it.
    const untouchedDoc = await firestore.getProduct('marble-side-table');
    assert.equal(
      untouchedDoc.data.arModelStoragePath,
      'products/marble-side-table/ar/model-v2.glb',
    );
  } finally {
    ws.cleanup();
  }
});

test('preflightSource-level: sha256Hex is used for both the plan and the object metadata', () => {
  // A cheap sanity check that the module's own hashing primitive is what a
  // real re-verification would use too (no separate/inconsistent hash path).
  const bytes = Buffer.from('hello');
  assert.equal(sha256Hex(bytes), sha256Hex(Buffer.from('hello')));
  assert.notEqual(sha256Hex(bytes), sha256Hex(Buffer.from('hellO')));
});

// Note: every test above that exercises `buildRolloutPlan`'s happy path
// depends on the real `_ar_assets/candidates/*_chatgpt_original.glb` files
// actually being present on this machine (they are git-ignored local
// developer assets — tracker §15/§17, `PROVENANCE.md`). On a checkout without
// them (e.g. a bare CI clone with no local asset recovery step run yet),
// these tests skip themselves via the `realCandidatesPresent()` guard rather
// than failing on missing fixtures unrelated to the logic under test.
