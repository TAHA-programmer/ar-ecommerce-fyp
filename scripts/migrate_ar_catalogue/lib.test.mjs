// Unit tests for the Phase 9.2 R13/R14 Room-AR catalogue recast core logic.
// `node --test lib.test.mjs` — no live Firebase needed.

import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AR_PRODUCT_IDS,
  BACKUP_SCHEMA_VERSION,
  DELETE_FIELD,
  MigrationAbort,
  RECAST,
  assertDimensionSignOff,
  assertProjectGuard,
  buildBackupPayload,
  buildFullPlan,
  commitRecast,
  commitRollback,
  finaliseBackup,
  migrationControlledKeys,
  planProduct,
  recastById,
  requiredStorageObjects,
  summarizePlans,
  validateBackup,
} from './lib.mjs';
import {
  SOFA_GALLERY,
  objectPathFor,
  sofaImageFields,
} from '../upload_sofa_gallery/sofa_gallery.mjs';

// ── fixtures: the exact pre-recast live shape of each product ────────────────

const GENERIC =
  'Elevate your space with this beautiful and functional piece. ' +
  'Crafted with attention to detail and high-quality materials.';

// The exact shape every real `products/{id}` document already has for the AR
// fields BEFORE this migration: `product_firestore_mapper.toFirestoreMap()`
// has always written the legacy Admin AR & Media mirror keys, as explicit
// `null` when unset, for every product — while the eight genuinely-new Phase
// 9.2 `ar*` keys are simply absent. This is the recognised legacy state.
const LEGACY_AR_MIRROR = { arModelAssetPath: null, arScale: null };

const PRE = {
  'luna-accent-chair': {
    title: 'Luna Accent Chair',
    experienceType: 'roomAr',
    priceAmount: 12000,
    stockQuantity: 10,
    categoryId: 'furniture',
    specifications: [
      { label: 'Material', value: 'Premium Fabric, Solid Wood' },
      { label: 'Dimensions', value: 'W 70 cm • D 72 cm • H 82 cm' },
    ],
    description:
      'The Luna Accent Chair brings a touch of mid-century modern elegance to ' +
      "your living space. With its sculptural silhouette, plush velvet " +
      "upholstery, and tapered brass legs, it's designed for both comfort and " +
      'statement-making style.',
    ...LEGACY_AR_MIRROR,
  },
  'glass-coffee-table': {
    title: 'Glass Coffee Table',
    experienceType: 'roomAr',
    priceAmount: 16500,
    categoryId: 'furniture',
    specifications: [],
    description: GENERIC,
    ...LEGACY_AR_MIRROR,
  },
  'modern-table-lamp': {
    title: 'Modern Table Lamp',
    experienceType: 'roomAr',
    priceAmount: 5500,
    categoryId: 'lighting',
    specifications: [
      { label: 'Material', value: 'Brass & Glass' },
      { label: 'Dimensions', value: 'H 45 cm • W 20 cm' },
      { label: 'Bulb Type', value: 'E27 LED' },
    ],
    description: GENERIC,
    ...LEGACY_AR_MIRROR,
  },
  'luna-3-seater-sofa': {
    title: 'Luna 3-Seater Sofa',
    experienceType: 'roomAr',
    priceAmount: 20000,
    categoryId: 'furniture',
    specifications: [
      { label: 'Material', value: 'Premium Fabric' },
      { label: 'Dimensions', value: 'W 200 cm • D 85 cm • H 82 cm' },
    ],
    description: GENERIC,
    mainImage: {
      path: 'assets/images/home/best_sellers/best_seller_sofa.png',
      source: 'asset',
      altText: '',
    },
    galleryMedia: Array.from({ length: 5 }, () => ({
      path: 'assets/images/home/best_sellers/best_seller_sofa.png',
      source: 'asset',
      altText: '',
    })),
    ...LEGACY_AR_MIRROR,
  },
};

const itemFor = (id) => recastById[id];

/** Storage verification where every sofa gallery object is present + matching. */
function stagedGallery() {
  const v = {};
  for (const item of SOFA_GALLERY) {
    v[objectPathFor(item)] = {
      exists: true,
      sizeBytes: item.expectedSizeBytes,
      sha256: item.expectedSha256,
      contentType: 'image/png',
    };
  }
  return v;
}

/**
 * A tiny in-memory Firestore with a genuine atomic transaction: `runTransaction`
 * buffers writes and applies them only if `fn` resolves; a throw discards the
 * whole buffer. Optionally injects a concurrent edit before commit.
 */
function fakeDb(docs, { concurrentEditBeforeCommit } = {}) {
  const store = new Map(
    Object.entries(docs).map(([id, data]) => [
      id,
      { data: structuredClone(data), updateTime: `t0-${id}` },
    ]),
  );
  let commits = 0;
  let docWrites = 0;
  return {
    _store: store,
    get commits() { return commits; },
    get docWrites() { return docWrites; },
    firestore: {
      async getProduct(id) {
        const e = store.get(id);
        return e
          ? { data: structuredClone(e.data), updateTime: e.updateTime }
          : { data: null, updateTime: null };
      },
    },
    async runTransaction(fn, _opts) {
      const buffer = [];
      const tx = {
        async get(id) {
          const e = store.get(id);
          return {
            exists: !!e,
            data: e ? structuredClone(e.data) : null,
            updateTime: e ? e.updateTime : null,
          };
        },
        update(id, fields) {
          buffer.push({ id, fields });
        },
      };
      const txAdapter = {
        get: tx.get,
        update(id, fields) {
          const translated = {};
          for (const [k, v] of Object.entries(fields)) translated[k] = v;
          tx.update(id, translated);
        },
      };
      const result = await fn({
        get: tx.get,
        update: (ref, fields) => tx.update(ref, fields),
        _txAdapter: txAdapter,
      });
      // simulate a racing writer landing right before our commit
      if (concurrentEditBeforeCommit) {
        const e = store.get(concurrentEditBeforeCommit);
        if (e) e.updateTime = `t-raced-${concurrentEditBeforeCommit}`;
        throw new MigrationAbort(
          `${concurrentEditBeforeCommit}: concurrent modification`,
        );
      }
      // atomic apply
      for (const { id, fields } of buffer) {
        const e = store.get(id);
        for (const [k, v] of Object.entries(fields)) {
          if (v === DELETE_FIELD) delete e.data[k];
          else e.data[k] = v;
        }
        e.updateTime = `t1-${id}`;
        docWrites++;
      }
      commits++;
      return result;
    },
  };
}

/** Runs the CLI-equivalent flow (preflight → transaction) against a fakeDb. */
async function runMigration(db, { storageVerification = stagedGallery() } = {}) {
  const storage = {
    async statObject(p) {
      return storageVerification[p] ?? { exists: false };
    },
  };
  const { plans, storageVerification: sv } = await buildFullPlan(
    db.firestore,
    storage,
  );
  const summary = summarizePlans(plans);
  if (summary.hasBlockers) return { plans, summary, committed: null };
  const changing = plans.filter((p) => p.wouldChange);
  const backup = buildBackupPayload(plans);
  if (changing.length === 0) return { plans, summary, committed: [], backup };
  // CLI parity: re-check EVERY target document inside the transaction.
  const targetPlans = plans.filter(
    (p) => p.status === 'needs-recast' || p.status === 'already-recast',
  );
  let committed = null;
  await db.runTransaction(async (tx) => {
    const txAdapter = {
      get: tx.get,
      update: (id, fields) => tx.update(id, fields),
    };
    committed = await commitRecast(targetPlans, txAdapter, sv);
    return committed;
  });
  return { plans, summary, committed, backup };
}

// ── tests ───────────────────────────────────────────────────────────────────

test('guards', () => {
  assert.doesNotThrow(() => assertProjectGuard('dry-run', null));
  assert.throws(() => assertProjectGuard('apply', 'other'));
  assert.doesNotThrow(() => assertProjectGuard('apply', 'twin-ar-d4d75'));
  assert.throws(() => assertDimensionSignOff('apply', false), /dimension sign-off/);
  assert.doesNotThrow(() => assertDimensionSignOff('apply', true));
});

test('RECAST covers exactly the four ids; sofa is storage-gated', () => {
  assert.deepEqual(RECAST.map((r) => r.productId).sort(), [...AR_PRODUCT_IDS].sort());
  const sofa = itemFor('luna-3-seater-sofa');
  assert.ok(sofa.fields.mainImage.storageObjects.length === 6);
  assert.ok(sofa.fields.galleryMedia.storageObjects.length === 6);
  assert.equal(requiredStorageObjects().length, 6);
  // chair: ar-only
  assert.deepEqual(Object.keys(itemFor('luna-accent-chair').fields), ['ar']);
});

test('genuine four-document atomic commit (one transaction, price/stock preserved)', async () => {
  const db = fakeDb(PRE);
  const { committed } = await runMigration(db);
  assert.deepEqual(committed.sort(), [...AR_PRODUCT_IDS].sort());
  assert.equal(db.commits, 1); // ONE transaction commit
  assert.equal(db.docWrites, 4);
  const sofa = db._store.get('luna-3-seater-sofa').data;
  assert.equal(sofa.title, 'Luna Right-Chaise Sectional Sofa');
  assert.equal(sofa.priceAmount, 20000);
  assert.equal(sofa.categoryId, 'furniture');
  assert.equal(sofa.arModelSha256, 'efd400046b265fd49d8d2b0382d378d230d625cb879740a3ef0697ca86c0d187');
  assert.deepEqual(sofa.mainImage, sofaImageFields().mainImage);
  assert.equal(sofa.galleryMedia.length, 6);
  // idempotent re-run
  const again = await runMigration(fakeDb(
    Object.fromEntries(AR_PRODUCT_IDS.map((id) => [id, db._store.get(id).data])),
  ));
  assert.equal(again.committed.length, 0);
  assert.ok(again.plans.every((p) => p.status === 'already-recast'));
});

test('zero writes when ANY document fails preflight', async () => {
  const docs = structuredClone(PRE);
  delete docs['modern-table-lamp'];
  const db = fakeDb(docs);
  const { summary, committed } = await runMigration(db);
  assert.equal(summary.hasBlockers, true);
  assert.equal(committed, null);
  assert.equal(db.commits, 0);
  assert.equal(db.docWrites, 0);
});

test('update-time / concurrent-modification rejection → nothing commits', async () => {
  const db = fakeDb(PRE);
  const storage = { async statObject(p) { return stagedGallery()[p] ?? { exists: false }; } };
  const { plans, storageVerification } = await buildFullPlan(db.firestore, storage);
  // mutate one doc's updateTime AFTER preflight, before the transaction
  db._store.get('glass-coffee-table').updateTime = 't-EDITED';
  await assert.rejects(
    () =>
      db.runTransaction(async (tx) => {
        const txAdapter = { get: tx.get, update: (id, f) => tx.update(id, f) };
        return commitRecast(plans, txAdapter, storageVerification);
      }),
    (e) => e instanceof MigrationAbort && /concurrent modification/.test(e.message),
  );
  assert.equal(db.commits, 0);
  assert.equal(db.docWrites, 0);
});

test('a racing writer landing during the transaction commits nothing', async () => {
  const db = fakeDb(PRE, { concurrentEditBeforeCommit: 'luna-3-seater-sofa' });
  await assert.rejects(() => runMigration(db), (e) => e instanceof MigrationAbort);
  assert.equal(db.commits, 0);
  assert.equal(db.docWrites, 0);
});

test('unexpected description → field-conflict, whole run blocked', async () => {
  const docs = structuredClone(PRE);
  docs['glass-coffee-table'].description = 'A sleek tempered-glass coffee table.';
  const db = fakeDb(docs);
  const { plans, committed } = await runMigration(db);
  assert.equal(committed, null);
  const p = plans.find((x) => x.productId === 'glass-coffee-table');
  assert.equal(p.status, 'field-conflict');
  assert.match(p.reason, /description/);
  assert.equal(db.docWrites, 0);
});

test('partially populated ar* metadata → blocked with a field-level diagnostic', async () => {
  const docs = structuredClone(PRE);
  docs['modern-table-lamp'].arModelStoragePath = 'products/modern-table-lamp/ar/model-v1.glb';
  // ... but NOT the other 8 keys
  const db = fakeDb(docs);
  const { plans } = await runMigration(db);
  const p = plans.find((x) => x.productId === 'modern-table-lamp');
  assert.equal(p.blocked, true);
  assert.match(p.reason, /partially populated|missing/);
});

test('ar* metadata present but wrong sha → blocked', async () => {
  const docs = structuredClone(PRE);
  const t = itemFor('luna-accent-chair').fields.ar.target;
  Object.assign(docs['luna-accent-chair'], t, { arModelSha256: 'f'.repeat(64) });
  const db = fakeDb(docs);
  const { plans } = await runMigration(db);
  const p = plans.find((x) => x.productId === 'luna-accent-chair');
  assert.equal(p.blocked, true);
  assert.match(p.reason, /arModelSha256/);
});

test('idempotent: fully-final doc → already-recast, zero writes', async () => {
  const done = structuredClone(PRE);
  for (const id of AR_PRODUCT_IDS) {
    const item = itemFor(id);
    for (const [name, fs] of Object.entries(item.fields)) {
      if (fs.arGroup) Object.assign(done[id], fs.target);
      else done[id][name] = fs.target;
    }
  }
  const db = fakeDb(done);
  const { plans, committed } = await runMigration(db);
  assert.ok(plans.every((p) => p.status === 'already-recast'));
  assert.equal(committed.length, 0);
  assert.equal(db.docWrites, 0);
});

test('sofa recast blocked when the gallery objects are absent', async () => {
  const db = fakeDb(PRE);
  const { plans, committed } = await runMigration(db, { storageVerification: {} });
  assert.equal(committed, null);
  const sofa = plans.find((p) => p.productId === 'luna-3-seater-sofa');
  assert.equal(sofa.blocked, true);
  assert.match(sofa.reason, /not staged/);
  // the other three are fine on their own, but the run is all-or-nothing
  assert.equal(summarizePlans(plans).hasBlockers, true);
});

test('sofa recast blocked when a gallery object has the wrong size/hash', async () => {
  const v = stagedGallery();
  const firstPath = objectPathFor(SOFA_GALLERY[0]);
  v[firstPath] = { exists: true, sizeBytes: 999, sha256: 'deadbeef' };
  const db = fakeDb(PRE);
  const { plans } = await runMigration(db, { storageVerification: v });
  const sofa = plans.find((p) => p.productId === 'luna-3-seater-sofa');
  assert.equal(sofa.blocked, true);
  assert.match(sofa.reason, /size 999|sha256/);
});

test('sofa idempotent even with unstaged gallery IF the doc already points at the final gallery', async () => {
  const docs = structuredClone(PRE);
  Object.assign(docs['luna-3-seater-sofa'], sofaImageFields());
  // also make the rest of the sofa final
  const item = itemFor('luna-3-seater-sofa');
  for (const [name, fs] of Object.entries(item.fields)) {
    if (fs.arGroup) Object.assign(docs['luna-3-seater-sofa'], fs.target);
    else if (name !== 'mainImage' && name !== 'galleryMedia') docs['luna-3-seater-sofa'][name] = fs.target;
  }
  const db = fakeDb(docs);
  const { plans } = await runMigration(db, { storageVerification: {} });
  const sofa = plans.find((p) => p.productId === 'luna-3-seater-sofa');
  assert.equal(sofa.status, 'already-recast');
});

test('atomic guarded rollback restores exact prior state; refuses if edited', async () => {
  const db = fakeDb(PRE);
  const { backup } = await runMigration(db);
  // finalise the backup with post-commit updateTimes (CLI does this)
  const post = {};
  for (const id of AR_PRODUCT_IDS) post[id] = db._store.get(id).updateTime;
  finaliseBackup(backup, post);
  assert.equal(backup.schemaVersion, BACKUP_SCHEMA_VERSION);

  // happy path: nothing changed since → rollback works, one transaction
  const commitsBefore = db.commits;
  const ids = await db.runTransaction(async (tx) => {
    const txAdapter = { get: tx.get, update: (id, f) => tx.update(id, f) };
    return commitRollback(backup, txAdapter);
  });
  assert.equal(db.commits, commitsBefore + 1);
  assert.deepEqual(ids.sort(), [...AR_PRODUCT_IDS].sort());
  const table = db._store.get('glass-coffee-table').data;
  assert.equal(table.title, 'Glass Coffee Table');
  assert.deepEqual(table.specifications, []);
  assert.equal('arModelStoragePath' in table, false); // deleted (absent before)
  assert.equal(table.priceAmount, 16500);

  // re-apply, then edit one doc → rollback must refuse
  const db2 = fakeDb(PRE);
  const r2 = await runMigration(db2);
  const post2 = {};
  for (const id of AR_PRODUCT_IDS) post2[id] = db2._store.get(id).updateTime;
  finaliseBackup(r2.backup, post2);
  db2._store.get('modern-table-lamp').updateTime = 't-LATER-EDIT';
  await assert.rejects(
    () =>
      db2.runTransaction(async (tx) => {
        const txAdapter = { get: tx.get, update: (id, f) => tx.update(id, f) };
        return commitRollback(r2.backup, txAdapter);
      }),
    (e) => e instanceof MigrationAbort && /edited since the migration/.test(e.message),
  );
  assert.equal(db2.commits, 1); // only the original recast
});

test('rollback refuses an un-finalised backup', async () => {
  const db = fakeDb(PRE);
  const { backup } = await runMigration(db); // NOT finalised
  await assert.rejects(
    () =>
      db.runTransaction(async (tx) => {
        const txAdapter = { get: tx.get, update: (id, f) => tx.update(id, f) };
        return commitRollback(backup, txAdapter);
      }),
    (e) => e instanceof MigrationAbort && /never finalised/.test(e.message),
  );
});

test('buildFullPlan performs zero writes', async () => {
  const db = fakeDb(PRE);
  const storage = { async statObject(p) { return stagedGallery()[p] ?? { exists: false }; } };
  await buildFullPlan(db.firestore, storage);
  assert.equal(db.docWrites, 0);
  assert.equal(db.commits, 0);
});

test('backup captures the exact before value/absence per written key', async () => {
  const db = fakeDb(PRE);
  const { plans } = await runMigration(fakeDb(PRE));
  const backup = buildBackupPayload(plans);
  const table = backup.entries.find((e) => e.productId === 'glass-coffee-table');
  assert.equal(table.before.title, 'Glass Coffee Table');
  assert.deepEqual(table.before.arModelStoragePath, { __absentBeforeMigration: true });
  assert.ok(table.writtenKeys.includes('description'));
  assert.ok(table.writtenKeys.includes('arWidthM'));
});

// ── final hardening pass ────────────────────────────────────────────────────

/** Make one product's document already exactly final (used to test the
 *  transaction re-checking documents it would NOT write). */
function makeFinal(docs, id) {
  const item = itemFor(id);
  for (const [name, fs] of Object.entries(item.fields)) {
    if (fs.arGroup) Object.assign(docs[id], fs.target);
    else docs[id][name] = fs.target;
  }
}

test('finding 1: drift in an ALREADY-FINAL target document aborts the whole transaction', async () => {
  const docs = structuredClone(PRE);
  makeFinal(docs, 'modern-table-lamp'); // lamp is already-recast at preflight
  const db = fakeDb(docs);
  const storage = {
    async statObject(p) { return stagedGallery()[p] ?? { exists: false }; },
  };
  const { plans, storageVerification } = await buildFullPlan(db.firestore, storage);
  assert.equal(
    plans.find((p) => p.productId === 'modern-table-lamp').status,
    'already-recast',
  );
  const targetPlans = plans.filter(
    (p) => p.status === 'needs-recast' || p.status === 'already-recast',
  );
  assert.equal(targetPlans.length, 4); // ALL four are re-checked, not just the 3 changing

  // the already-final lamp is edited between preflight and commit
  db._store.get('modern-table-lamp').updateTime = 't-LAMP-EDITED';
  await assert.rejects(
    () =>
      db.runTransaction(async (tx) => {
        const txAdapter = { get: tx.get, update: (id, f) => tx.update(id, f) };
        return commitRecast(targetPlans, txAdapter, storageVerification);
      }),
    (e) =>
      e instanceof MigrationAbort &&
      /modern-table-lamp/.test(e.message) &&
      /concurrent modification/.test(e.message),
  );
  assert.equal(db.commits, 0);
  assert.equal(db.docWrites, 0);
});

test('finding 1: a target document that legacy→drifts before commit aborts with zero writes', async () => {
  const docs = structuredClone(PRE);
  makeFinal(docs, 'modern-table-lamp');
  const db = fakeDb(docs);
  const storage = {
    async statObject(p) { return stagedGallery()[p] ?? { exists: false }; },
  };
  const { plans, storageVerification } = await buildFullPlan(db.firestore, storage);
  const targetPlans = plans.filter(
    (p) => p.status === 'needs-recast' || p.status === 'already-recast',
  );
  // lamp description is hand-edited to an unrecognised value (and updateTime moves)
  db._store.get('modern-table-lamp').data.description = 'hand edited';
  db._store.get('modern-table-lamp').updateTime = 't-LAMP-EDITED';
  await assert.rejects(
    () =>
      db.runTransaction(async (tx) => {
        const txAdapter = { get: tx.get, update: (id, f) => tx.update(id, f) };
        return commitRecast(targetPlans, txAdapter, storageVerification);
      }),
    (e) => e instanceof MigrationAbort,
  );
  assert.equal(db.commits, 0);
  assert.equal(db.docWrites, 0);
});

test('finding 2: sofa gallery object missing its sha256 metadata blocks the migration', async () => {
  const v = stagedGallery();
  const firstPath = objectPathFor(SOFA_GALLERY[0]);
  v[firstPath] = {
    exists: true,
    sizeBytes: SOFA_GALLERY[0].expectedSizeBytes,
    sha256: null,
    contentType: 'image/png',
  };
  const { plans } = await runMigration(fakeDb(PRE), { storageVerification: v });
  const sofa = plans.find((p) => p.productId === 'luna-3-seater-sofa');
  assert.equal(sofa.blocked, true);
  assert.match(sofa.reason, /missing twinArSofaGallerySha256/);
});

test('finding 2: sofa gallery object with no byte size blocks the migration', async () => {
  const v = stagedGallery();
  const firstPath = objectPathFor(SOFA_GALLERY[0]);
  v[firstPath] = {
    exists: true,
    sizeBytes: null,
    sha256: SOFA_GALLERY[0].expectedSha256,
    contentType: 'image/png',
  };
  const { plans } = await runMigration(fakeDb(PRE), { storageVerification: v });
  const sofa = plans.find((p) => p.productId === 'luna-3-seater-sofa');
  assert.equal(sofa.blocked, true);
  assert.match(sofa.reason, /reports no byte size/);
});

test('finding 2: sofa gallery object with the wrong content type blocks the migration', async () => {
  const v = stagedGallery();
  const firstPath = objectPathFor(SOFA_GALLERY[0]);
  v[firstPath] = { ...v[firstPath], contentType: 'application/octet-stream' };
  const { plans } = await runMigration(fakeDb(PRE), { storageVerification: v });
  const sofa = plans.find((p) => p.productId === 'luna-3-seater-sofa');
  assert.equal(sofa.blocked, true);
  assert.match(sofa.reason, /contentType/);
});

test('finding 3: a product mixing a final field with a legacy field is blocked for review', async () => {
  const docs = structuredClone(PRE);
  // table: title already recast to the FINAL value, description still legacy
  docs['glass-coffee-table'].title = 'Round Wood Coffee Table';
  const db = fakeDb(docs);
  const { plans, committed } = await runMigration(db);
  assert.equal(committed, null);
  const p = plans.find((x) => x.productId === 'glass-coffee-table');
  assert.equal(p.status, 'field-conflict');
  assert.match(p.reason, /mixed legacy\/final/);
  assert.match(p.reason, /title/);
  assert.equal(db.docWrites, 0);
});

test('finding 3: the lamp (legacy title == final title) is NOT flagged as mixed', async () => {
  // PRE lamp already has the final title; description/specs/ar are legacy.
  const db = fakeDb(PRE);
  const { plans } = await runMigration(db);
  const lamp = plans.find((p) => p.productId === 'modern-table-lamp');
  assert.equal(lamp.blocked, false);
  assert.equal(lamp.status, 'needs-recast');
  assert.equal('title' in lamp.write, false); // already correct — never re-written
});

test('finding 3: partial ar* metadata still blocks', async () => {
  const docs = structuredClone(PRE);
  docs['glass-coffee-table'].arModelStoragePath =
    'products/glass-coffee-table/ar/model-v1.glb';
  const { plans } = await runMigration(fakeDb(docs));
  const p = plans.find((x) => x.productId === 'glass-coffee-table');
  assert.equal(p.blocked, true);
  assert.match(p.reason, /partially populated|missing/);
});

test('finding 4: migrationControlledKeys is the exact per-product write allowlist', () => {
  assert.deepEqual(
    [...migrationControlledKeys('luna-accent-chair')].sort(),
    [
      'arDepthM', 'arHeightM', 'arModelFormat', 'arModelSha256',
      'arModelStoragePath', 'arModelVersion', 'arScale', 'arScaleContract',
      'arWidthM',
    ].sort(),
  );
  const sofa = [...migrationControlledKeys('luna-3-seater-sofa')];
  for (const k of ['title', 'description', 'specifications', 'mainImage', 'galleryMedia']) {
    assert.ok(sofa.includes(k), k);
  }
  assert.equal(sofa.length, 14);
  assert.equal(migrationControlledKeys('not-a-product'), null);
});

test('finding 4: validateBackup rejects tampered / corrupted backups', async () => {
  const db = fakeDb(PRE);
  const { backup } = await runMigration(db);
  const post = {};
  for (const id of AR_PRODUCT_IDS) post[id] = db._store.get(id).updateTime;
  finaliseBackup(backup, post);
  assert.doesNotThrow(() => validateBackup(backup)); // genuine backup is valid

  const dup = structuredClone(backup);
  dup.entries[1].productId = dup.entries[0].productId;
  assert.throws(() => validateBackup(dup), /more than once/);

  const alien = structuredClone(backup);
  const te = alien.entries.find((e) => e.productId === 'glass-coffee-table');
  te.writtenKeys.push('priceAmount');
  te.finalTarget.priceAmount = 1;
  te.before.priceAmount = 999;
  assert.throws(
    () => validateBackup(alien),
    /not in this product's migration-controlled allowlist/,
  );

  const mismatch = structuredClone(backup);
  const me = mismatch.entries.find((e) => e.productId === 'glass-coffee-table');
  delete me.finalTarget[me.writtenKeys[0]];
  assert.throws(() => validateBackup(mismatch), /finalTarget keys do not exactly match/);

  const dk = structuredClone(backup);
  const dke = dk.entries.find((e) => e.productId === 'glass-coffee-table');
  dke.writtenKeys.push(dke.writtenKeys[0]);
  assert.throws(() => validateBackup(dk), /more than once/);

  const bad = structuredClone(backup);
  const be = bad.entries.find((e) => e.productId === 'glass-coffee-table');
  const absentKey = be.writtenKeys.find(
    (k) => be.before[k] && be.before[k].__absentBeforeMigration,
  );
  be.before[absentKey] = { __absentBeforeMigration: 'yes', extra: 1 };
  assert.throws(() => validateBackup(bad), /malformed absent-sentinel/);

  const unk = structuredClone(backup);
  unk.entries[0].productId = 'totally-unknown';
  assert.throws(() => validateBackup(unk), /unknown product/);

  const notFinal = structuredClone(backup);
  delete notFinal.entries[0].updateTimeAfterApply;
  assert.throws(() => validateBackup(notFinal), /never finalised/);
});

// ── live `arScale: null` compatibility (the real blocker) ───────────────────

test('LIVE STATE: `arScale: null` + 8 new ar* keys absent classifies as legacy and recasts', async () => {
  // This is EXACTLY what every live `products/{id}` doc looks like:
  // `product_firestore_mapper` has always written arModelAssetPath+arScale as
  // explicit null; the eight Phase-9.2 keys are absent.
  for (const id of AR_PRODUCT_IDS) {
    assert.equal(PRE[id].arScale, null, `${id} fixture must carry arScale: null`);
    assert.equal('arModelStoragePath' in PRE[id], false);
  }
  const db = fakeDb(PRE);
  const { plans, summary, committed } = await runMigration(db);

  assert.equal(summary.hasBlockers, false, JSON.stringify(summary.blockers));
  assert.deepEqual(committed.sort(), [...AR_PRODUCT_IDS].sort());
  assert.equal(db.commits, 1);
  assert.equal(db.docWrites, 4);

  for (const id of AR_PRODUCT_IDS) {
    const p = plans.find((x) => x.productId === id);
    assert.equal(p.status, 'needs-recast', id);
    // all 9 ar* keys written, arScale flips null -> 1.0
    assert.equal(p.write.arScale, 1.0, id);
    assert.equal(typeof p.write.arModelSha256, 'string', id);
    assert.equal(p.before.arScale, null, id); // present-null, NOT absent
    const doc = db._store.get(id).data;
    assert.equal(doc.arScale, 1.0, id);
    assert.equal(doc.arModelFormat, 'glb', id);
    assert.equal(doc.arModelAssetPath, null, id); // untouched legacy mirror
  }
});

test('LIVE STATE: `arScale` absent entirely (older docs) is also legacy', async () => {
  const docs = structuredClone(PRE);
  for (const id of AR_PRODUCT_IDS) delete docs[id].arScale;
  const { plans, summary } = await runMigration(fakeDb(docs));
  assert.equal(summary.hasBlockers, false);
  for (const id of AR_PRODUCT_IDS) {
    assert.equal(plans.find((x) => x.productId === id).status, 'needs-recast', id);
  }
});

test('LIVE STATE: idempotent re-run after the arScale:null recast → already-recast', async () => {
  const db = fakeDb(PRE);
  await runMigration(db);
  const again = await runMigration(
    fakeDb(Object.fromEntries(AR_PRODUCT_IDS.map((id) => [id, db._store.get(id).data]))),
  );
  assert.equal(again.committed.length, 0);
  assert.ok(again.plans.every((p) => p.status === 'already-recast'));
});

test('a GENUINE partial ar* (arScale:null + one real new key) still blocks', async () => {
  const docs = structuredClone(PRE);
  docs['modern-table-lamp'].arWidthM = 0.2; // one real key, contract incomplete
  const { plans } = await runMigration(fakeDb(docs));
  const p = plans.find((x) => x.productId === 'modern-table-lamp');
  assert.equal(p.blocked, true);
  assert.match(p.reason, /partially populated — present: arWidthM/);
});

test('`arScale` holding an unexpected non-null value (no rest of contract) blocks', async () => {
  const docs = structuredClone(PRE);
  docs['glass-coffee-table'].arScale = 2.0; // legacy admin scale, no ar* contract
  const { plans } = await runMigration(fakeDb(docs));
  const p = plans.find((x) => x.productId === 'glass-coffee-table');
  assert.equal(p.blocked, true);
  assert.match(p.reason, /arScale=2 set without the rest of the contract/);
});

test('rollback restores `arScale` to its present-null legacy value, not deletion', async () => {
  const db = fakeDb(PRE);
  const { backup } = await runMigration(db);
  const post = {};
  for (const id of AR_PRODUCT_IDS) post[id] = db._store.get(id).updateTime;
  finaliseBackup(backup, post);

  await db.runTransaction(async (tx) => {
    const txAdapter = { get: tx.get, update: (id, f) => tx.update(id, f) };
    return commitRollback(backup, txAdapter);
  });
  for (const id of AR_PRODUCT_IDS) {
    const doc = db._store.get(id).data;
    assert.equal('arScale' in doc, true, `${id}: arScale key kept`);
    assert.equal(doc.arScale, null, `${id}: arScale restored to null`);
    assert.equal('arModelStoragePath' in doc, false, `${id}: new key deleted`);
    assert.equal(doc.arModelAssetPath, null, `${id}: legacy mirror untouched`);
  }
});
