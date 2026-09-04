import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  applyProductMigration,
  applyRollback,
  assertProjectGuard,
  buildBackupPayload,
  buildFullPlan,
  buildUpdatedFields,
  CONFIRMED_PROJECT_ID,
  collectUploadsForProduct,
  computeStableFileName,
  planProduct,
  summarizePlans,
  validateAssetFile,
} from './lib.mjs';

// ---------------------------------------------------------------------------
// Test fixtures: a temp "repo root" with real small image files on disk, and
// in-memory fake Firestore/Storage adapters matching the interfaces
// migrate_product_images.mjs wires to the real Admin SDK.
// ---------------------------------------------------------------------------

let repoRoot;

before(() => {
  repoRoot = mkdtempSync(path.join(os.tmpdir(), 'twinar-migrate-test-'));
});

after(() => {
  rmSync(repoRoot, { recursive: true, force: true });
});

function writeAsset(relPath, bytes) {
  const abs = path.join(repoRoot, relPath);
  mkdirSync(path.dirname(abs), { recursive: true });
  writeFileSync(abs, bytes);
  return relPath;
}

const IMG_A = () => writeAsset('assets/images/test/a.png', Buffer.from('image-a-bytes'));
const IMG_B = () => writeAsset('assets/images/test/b.png', Buffer.from('image-b-bytes'));

function assetRef(relPath, altText = '') {
  return { path: relPath, source: 'asset', altText };
}
function networkRef(url, altText = '') {
  return { path: url, source: 'network', altText };
}

class FakeFirestoreAdapter {
  constructor(productsById) {
    this.docs = new Map(
      Object.entries(productsById).map(([id, data]) => [id, structuredClone(data)]),
    );
    this.updateCalls = [];
    this.failUpdateFor = new Set();
  }
  async listProducts() {
    return [...this.docs.entries()].map(([id, data]) => ({
      id,
      data: structuredClone(data),
    }));
  }
  async updateProduct(id, fields) {
    if (this.failUpdateFor.has(id)) {
      throw new Error(`simulated Firestore update failure for ${id}`);
    }
    if (!this.docs.has(id)) throw new Error(`no such product ${id}`);
    const doc = this.docs.get(id);
    Object.assign(doc, structuredClone(fields));
    this.updateCalls.push({ id, fields: structuredClone(fields) });
  }
}

class FakeStorageAdapter {
  constructor() {
    this.objects = new Map();
    this.deleteCalls = [];
    this.uploadCallCount = 0;
    this.failUploadOnCallNumber = null;
  }
  async exists(objectPath) {
    return this.objects.has(objectPath);
  }
  async upload(objectPath, buffer, contentType) {
    this.uploadCallCount++;
    if (this.failUploadOnCallNumber === this.uploadCallCount) {
      throw new Error('simulated partial-batch upload failure');
    }
    this.objects.set(objectPath, { buffer, contentType });
  }
  async delete(objectPath) {
    this.deleteCalls.push(objectPath);
    this.objects.delete(objectPath);
  }
  publicUrl(objectPath) {
    return `https://fake-storage.test/${objectPath}`;
  }
}

// ---------------------------------------------------------------------------

describe('validateAssetFile', () => {
  it('accepts a valid small png', () => {
    const rel = IMG_A();
    const result = validateAssetFile(repoRoot, rel);
    assert.equal(result.ok, true);
    assert.equal(result.contentType, 'image/png');
  });

  it('rejects a missing file', () => {
    const result = validateAssetFile(repoRoot, 'assets/images/test/does-not-exist.png');
    assert.equal(result.ok, false);
    assert.match(result.reason, /not found/i);
  });

  it('rejects an unsupported extension', () => {
    const rel = writeAsset('assets/images/test/model.glb', Buffer.from('binary'));
    const result = validateAssetFile(repoRoot, rel);
    assert.equal(result.ok, false);
    assert.match(result.reason, /unsupported/i);
  });

  it('rejects a file over the 10MB product-image limit', () => {
    const rel = writeAsset(
      'assets/images/test/huge.png',
      Buffer.alloc(10 * 1024 * 1024 + 1, 1),
    );
    const result = validateAssetFile(repoRoot, rel);
    assert.equal(result.ok, false);
    assert.match(result.reason, /too large/i);
  });
});

describe('computeStableFileName', () => {
  it('is deterministic for identical bytes', () => {
    const a = computeStableFileName(Buffer.from('same bytes'), '.png');
    const b = computeStableFileName(Buffer.from('same bytes'), '.png');
    assert.equal(a, b);
  });

  it('differs for different bytes', () => {
    const a = computeStableFileName(Buffer.from('bytes one'), '.png');
    const b = computeStableFileName(Buffer.from('bytes two'), '.png');
    assert.notEqual(a, b);
  });
});

describe('planProduct — mixed asset/network galleries', () => {
  it('migrates only asset entries and preserves network entries unchanged', () => {
    const imgA = IMG_A();
    const data = {
      mainImage: assetRef(imgA, 'Main alt'),
      galleryMedia: [
        assetRef(imgA, 'Gallery alt 1'),
        networkRef('https://existing.example/already-migrated.jpg', 'Already there'),
      ],
    };
    const plan = planProduct('prod-mixed', data, repoRoot);

    assert.equal(plan.blocked, false);
    assert.equal(plan.wouldChange, true);
    assert.equal(plan.mainImage.kind, 'asset-valid');
    assert.equal(plan.galleryMedia[0].kind, 'asset-valid');
    assert.equal(plan.galleryMedia[1].kind, 'network');
    assert.equal(plan.networkSkipCount, 1);

    const updated = buildUpdatedFields(
      plan,
      new Map([[plan.mainImage.stableFileName, 'https://new.example/uploaded.png']]),
    );
    assert.equal(updated.mainImage.source, 'network');
    assert.equal(updated.mainImage.path, 'https://new.example/uploaded.png');
    assert.equal(updated.mainImage.altText, 'Main alt');
    // Network entry passed through byte-for-byte unchanged.
    assert.deepEqual(updated.galleryMedia[1], data.galleryMedia[1]);
  });
});

describe('planProduct — missing/invalid files block the whole product', () => {
  it('blocks the product and reports the bad path, migrating nothing', () => {
    const imgA = IMG_A();
    const data = {
      mainImage: assetRef(imgA),
      galleryMedia: [assetRef('assets/images/test/missing.png')],
    };
    const plan = planProduct('prod-broken', data, repoRoot);

    assert.equal(plan.blocked, true);
    assert.equal(plan.wouldChange, false);
    assert.equal(plan.invalid.length, 1);
    assert.equal(plan.invalid[0].originalRef.path, 'assets/images/test/missing.png');
  });
});

describe('collectUploadsForProduct — within-product dedup', () => {
  it('collapses duplicate gallery references to the same source file into one upload', () => {
    const imgA = IMG_A();
    const data = {
      mainImage: assetRef(imgA),
      galleryMedia: [assetRef(imgA), assetRef(imgA), assetRef(imgA)],
    };
    const plan = planProduct('prod-dupe', data, repoRoot);
    const uploads = collectUploadsForProduct(plan);
    assert.equal(uploads.length, 1);
  });
});

describe('buildFullPlan + summarizePlans — dry run', () => {
  it('reports counts with no writes attempted', async () => {
    const imgA = IMG_A();
    const firestore = new FakeFirestoreAdapter({
      'prod-1': { mainImage: assetRef(imgA), galleryMedia: [assetRef(imgA)] },
      'prod-2': {
        mainImage: networkRef('https://already.example/x.jpg'),
        galleryMedia: [],
      },
      'prod-3': {
        mainImage: assetRef(imgA),
        galleryMedia: [assetRef('assets/images/test/missing2.png')],
      },
    });

    const plans = await buildFullPlan(firestore, repoRoot);
    const summary = summarizePlans(plans);

    assert.equal(summary.productsScanned, 3);
    assert.deepEqual(summary.documentsThatWouldChange, ['prod-1']);
    assert.deepEqual(summary.documentsBlocked, ['prod-3']);
    assert.equal(summary.documentsUntouched, 1); // prod-2
    assert.equal(summary.missingOrInvalid.length, 1);
    assert.equal(firestore.updateCalls.length, 0); // dry run never writes
  });
});

describe('applyProductMigration — happy path + primary/order/altText preservation', () => {
  it('uploads staged images, updates only mainImage/galleryMedia, preserves order and alt text', async () => {
    const imgA = IMG_A();
    const imgB = IMG_B();
    const originalData = {
      title: 'Untouched Product',
      priceAmount: 1000,
      mainImage: assetRef(imgB, 'Primary'),
      galleryMedia: [assetRef(imgA, 'First'), assetRef(imgB, 'Second (same as primary)')],
    };
    const firestore = new FakeFirestoreAdapter({ 'prod-1': originalData });
    const storage = new FakeStorageAdapter();

    const plan = planProduct('prod-1', originalData, repoRoot);
    const result = await applyProductMigration(plan, {
      firestoreAdapter: firestore,
      storageAdapter: storage,
    });

    assert.equal(result.ok, true);
    // Two distinct source files (a, b) -> exactly two uploaded objects,
    // even though the gallery references b twice (main + gallery[1]).
    assert.equal(result.uploadedCount, 2);

    const updatedDoc = firestore.docs.get('prod-1');
    assert.equal(updatedDoc.title, 'Untouched Product'); // unrelated field untouched
    assert.equal(updatedDoc.priceAmount, 1000);
    assert.equal(updatedDoc.mainImage.source, 'network');
    assert.equal(updatedDoc.mainImage.altText, 'Primary');
    assert.equal(updatedDoc.galleryMedia.length, 2);
    assert.equal(updatedDoc.galleryMedia[0].altText, 'First');
    assert.equal(updatedDoc.galleryMedia[1].altText, 'Second (same as primary)');
    // mainImage and gallery[1] came from the same source file -> same URL.
    assert.equal(updatedDoc.mainImage.path, updatedDoc.galleryMedia[1].path);
    // gallery[0] came from a different source file -> different URL.
    assert.notEqual(updatedDoc.galleryMedia[0].path, updatedDoc.mainImage.path);
  });
});

describe('applyProductMigration — idempotent reruns', () => {
  it('does not re-upload or duplicate objects, and produces the same URLs on a second run', async () => {
    const imgA = IMG_A();
    const data1 = {
      mainImage: assetRef(imgA),
      galleryMedia: [assetRef(imgA)],
    };
    const firestore1 = new FakeFirestoreAdapter({ 'prod-1': data1 });
    const storage = new FakeStorageAdapter();

    const plan1 = planProduct('prod-1', data1, repoRoot);
    const first = await applyProductMigration(plan1, {
      firestoreAdapter: firestore1,
      storageAdapter: storage,
    });
    assert.equal(first.ok, true);
    assert.equal(first.uploadedCount, 1);
    const firstUrl = firestore1.docs.get('prod-1').mainImage.path;

    // Simulate a rerun against a FRESH product doc that still has the
    // original asset refs (e.g. the first run's Firestore write hadn't
    // happened yet, or a different product reuses the same source file) but
    // the SAME storage bucket state (the object from the first run persists).
    const firestore2 = new FakeFirestoreAdapter({ 'prod-1': data1 });
    const plan2 = planProduct('prod-1', data1, repoRoot);
    const second = await applyProductMigration(plan2, {
      firestoreAdapter: firestore2,
      storageAdapter: storage,
    });

    assert.equal(second.ok, true);
    assert.equal(second.uploadedCount, 0); // reused the existing object, no new upload
    assert.equal(storage.uploadCallCount, 1); // still only ever uploaded once total
    assert.equal(firestore2.docs.get('prod-1').mainImage.path, firstUrl);
  });

  it('skips products whose references are already all-network', async () => {
    const data = {
      mainImage: networkRef('https://already.example/main.jpg'),
      galleryMedia: [networkRef('https://already.example/g1.jpg')],
    };
    const plan = planProduct('prod-done', data, repoRoot);
    assert.equal(plan.wouldChange, false);
    assert.equal(plan.networkSkipCount, 2);
  });
});

describe('applyProductMigration — partial upload failure', () => {
  it('rolls back only the object it just created and leaves the document untouched', async () => {
    const imgA = IMG_A();
    const imgB = IMG_B();
    const data = {
      mainImage: assetRef(imgA),
      galleryMedia: [assetRef(imgB)],
    };
    const firestore = new FakeFirestoreAdapter({ 'prod-1': data });
    const storage = new FakeStorageAdapter();
    storage.failUploadOnCallNumber = 2; // first upload (imgA) succeeds, second (imgB) fails

    const plan = planProduct('prod-1', data, repoRoot);
    const result = await applyProductMigration(plan, {
      firestoreAdapter: firestore,
      storageAdapter: storage,
    });

    assert.equal(result.ok, false);
    assert.equal(result.rolledBackObjectPaths.length, 1);
    assert.equal(storage.deleteCalls.length, 1);
    assert.equal(storage.objects.size, 0); // rolled back, nothing left behind
    assert.equal(firestore.updateCalls.length, 0); // document never touched
    assert.deepEqual(firestore.docs.get('prod-1'), data); // exactly as before
  });

  it('leaves the document intact and rolls back new objects when the Firestore write itself fails', async () => {
    const imgA = IMG_A();
    const data = { mainImage: assetRef(imgA), galleryMedia: [] };
    const firestore = new FakeFirestoreAdapter({ 'prod-1': data });
    firestore.failUpdateFor.add('prod-1');
    const storage = new FakeStorageAdapter();

    const plan = planProduct('prod-1', data, repoRoot);
    const result = await applyProductMigration(plan, {
      firestoreAdapter: firestore,
      storageAdapter: storage,
    });

    assert.equal(result.ok, false);
    assert.equal(storage.deleteCalls.length, 1); // the just-uploaded object is rolled back
    assert.equal(storage.objects.size, 0);
    assert.deepEqual(firestore.docs.get('prod-1'), data); // untouched
  });
});

describe('project guard', () => {
  it('allows dry-run mode with no project argument', () => {
    assert.doesNotThrow(() => assertProjectGuard('dry-run', null));
  });

  it('allows rollback-dry-run mode with no project argument', () => {
    assert.doesNotThrow(() => assertProjectGuard('rollback-dry-run', null));
  });

  it('refuses apply mode with no project argument', () => {
    assert.throws(() => assertProjectGuard('apply', null), /Refusing to run live writes/);
  });

  it('refuses apply mode with the wrong project id', () => {
    assert.throws(
      () => assertProjectGuard('apply', 'some-other-project'),
      /Refusing to run live writes/,
    );
  });

  it('allows apply mode with exactly the confirmed project id', () => {
    assert.doesNotThrow(() => assertProjectGuard('apply', CONFIRMED_PROJECT_ID));
  });

  it('refuses rollback-apply mode with the wrong project id', () => {
    assert.throws(
      () => assertProjectGuard('rollback-apply', 'wrong'),
      /Refusing to run live writes/,
    );
  });
});

describe('backup + rollback', () => {
  it('backs up only changing products, with their original field values', async () => {
    const imgA = IMG_A();
    const firestore = new FakeFirestoreAdapter({
      'prod-1': { mainImage: assetRef(imgA), galleryMedia: [assetRef(imgA, 'g1')] },
      'prod-2': { mainImage: networkRef('https://already.example/x.jpg'), galleryMedia: [] },
    });
    const plans = await buildFullPlan(firestore, repoRoot);
    const backup = buildBackupPayload(plans);

    assert.equal(backup.length, 1);
    assert.equal(backup[0].productId, 'prod-1');
    assert.equal(backup[0].mainImage.source, 'asset');
    assert.equal(backup[0].mainImage.path, imgA);
    assert.equal(backup[0].galleryMedia[0].altText, 'g1');
  });

  it('restores a product to its backed-up original values', async () => {
    const imgA = IMG_A();
    const original = { mainImage: assetRef(imgA, 'orig'), galleryMedia: [assetRef(imgA, 'orig-g')] };
    const firestore = new FakeFirestoreAdapter({
      'prod-1': {
        mainImage: networkRef('https://migrated.example/main.png', 'orig'),
        galleryMedia: [networkRef('https://migrated.example/g.png', 'orig-g')],
      },
    });

    const results = await applyRollback(
      [{ productId: 'prod-1', mainImage: original.mainImage, galleryMedia: original.galleryMedia }],
      firestore,
    );

    assert.equal(results[0].ok, true);
    const restored = firestore.docs.get('prod-1');
    assert.deepEqual(restored.mainImage, original.mainImage);
    assert.deepEqual(restored.galleryMedia, original.galleryMedia);
  });

  it('reports a rollback failure for an unknown product without throwing', async () => {
    const firestore = new FakeFirestoreAdapter({});
    const results = await applyRollback(
      [{ productId: 'ghost', mainImage: networkRef('x'), galleryMedia: [] }],
      firestore,
    );
    assert.equal(results[0].ok, false);
    assert.match(results[0].error, /no such product/);
  });
});
