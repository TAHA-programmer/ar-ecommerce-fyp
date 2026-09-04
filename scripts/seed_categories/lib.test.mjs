import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';

import {
  CONFIRMED_PROJECT_ID,
  assertProjectGuard,
  computeStableFileName,
  runSeed,
  seedOneCategory,
  validateSeedImageFile,
} from './lib.mjs';

let repoRoot;

before(() => {
  repoRoot = mkdtempSync(path.join(os.tmpdir(), 'twinar-seed-categories-test-'));
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

function entry(key, overrides = {}) {
  return {
    key,
    name: key[0].toUpperCase() + key.slice(1),
    kind: key,
    sortOrder: 10,
    sourceImageAssetPath: writeAsset(
      `assets/images/home/categories/category_${key}.png`,
      Buffer.from(`bytes-for-${key}`),
    ),
    ...overrides,
  };
}

class FakeFirestoreAdapter {
  constructor(initialDocs = {}) {
    this.docs = new Map(Object.entries(initialDocs));
    this.createCalls = [];
    this.failCreateFor = new Set();
  }
  async getCategory(key) {
    return this.docs.has(key) ? { ...this.docs.get(key) } : null;
  }
  async createCategory(key, data) {
    if (this.failCreateFor.has(key)) {
      throw new Error(`simulated Firestore create failure for ${key}`);
    }
    this.docs.set(key, { ...data });
    this.createCalls.push({ key, data });
  }
}

class FakeStorageAdapter {
  constructor() {
    this.objects = new Map();
    this.deleteCalls = [];
    this.uploadCallCount = 0;
  }
  async exists(objectPath) {
    return this.objects.has(objectPath);
  }
  async upload(objectPath, buffer, contentType) {
    this.uploadCallCount++;
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

describe('validateSeedImageFile', () => {
  it('accepts a valid small png', () => {
    const rel = writeAsset('assets/images/home/categories/valid.png', Buffer.from('img'));
    const result = validateSeedImageFile(repoRoot, rel);
    assert.equal(result.ok, true);
    assert.equal(result.contentType, 'image/png');
  });

  it('rejects a missing file', () => {
    const result = validateSeedImageFile(repoRoot, 'assets/images/home/categories/missing.png');
    assert.equal(result.ok, false);
    assert.match(result.reason, /not found/i);
  });

  it('rejects an unsupported extension', () => {
    const rel = writeAsset('assets/images/home/categories/model.glb', Buffer.from('bin'));
    const result = validateSeedImageFile(repoRoot, rel);
    assert.equal(result.ok, false);
    assert.match(result.reason, /unsupported/i);
  });

  it('rejects a file over the 5MB category-image limit', () => {
    const rel = writeAsset(
      'assets/images/home/categories/huge.png',
      Buffer.alloc(5 * 1024 * 1024 + 1, 1),
    );
    const result = validateSeedImageFile(repoRoot, rel);
    assert.equal(result.ok, false);
    assert.match(result.reason, /too large/i);
  });
});

describe('computeStableFileName', () => {
  it('is deterministic for identical bytes', () => {
    const a = computeStableFileName(Buffer.from('x'), '.png');
    const b = computeStableFileName(Buffer.from('x'), '.png');
    assert.equal(a, b);
  });
});

describe('seedOneCategory — creation', () => {
  it('uploads the image and creates the document when absent', async () => {
    const firestore = new FakeFirestoreAdapter();
    const storage = new FakeStorageAdapter();
    const result = await seedOneCategory(entry('furniture'), {
      repoRoot,
      firestoreAdapter: firestore,
      storageAdapter: storage,
      force: false,
    });

    assert.equal(result.ok, true);
    assert.equal(result.skipped, false);
    assert.equal(storage.uploadCallCount, 1);
    const doc = await firestore.getCategory('furniture');
    assert.equal(doc.name, 'Furniture');
    assert.equal(doc.key, 'furniture');
    assert.equal(doc.kind, 'furniture');
    assert.equal(doc.isActive, true);
    assert.equal(doc.sortOrder, 10);
    assert.match(doc.imageUrl, /^https:\/\//);
    // Persisted imageUrl must be a real Storage URL, never the bundled
    // asset path.
    assert.doesNotMatch(doc.imageUrl, /assets\//);
  });

  it('reports missing/invalid source images without touching Firestore/Storage', async () => {
    const firestore = new FakeFirestoreAdapter();
    const storage = new FakeStorageAdapter();
    const badEntry = entry('clothing', {
      sourceImageAssetPath: 'assets/images/home/categories/does-not-exist.png',
    });
    const result = await seedOneCategory(badEntry, {
      repoRoot,
      firestoreAdapter: firestore,
      storageAdapter: storage,
      force: false,
    });

    assert.equal(result.ok, false);
    assert.match(result.reason, /not found/i);
    assert.equal(await firestore.getCategory('clothing'), null);
    assert.equal(storage.uploadCallCount, 0);
  });
});

describe('seedOneCategory — idempotency / preserving Admin edits', () => {
  it('skips an existing document on a normal rerun, uploading nothing', async () => {
    const firestore = new FakeFirestoreAdapter({
      furniture: {
        name: 'Renamed By Admin',
        key: 'furniture',
        kind: 'furniture',
        imageUrl: 'https://already.example/admin-uploaded.png',
        isActive: false,
        sortOrder: 999,
      },
    });
    const storage = new FakeStorageAdapter();
    const result = await seedOneCategory(entry('furniture'), {
      repoRoot,
      firestoreAdapter: firestore,
      storageAdapter: storage,
      force: false,
    });

    assert.equal(result.ok, true);
    assert.equal(result.skipped, true);
    assert.equal(storage.uploadCallCount, 0);
    // Admin's edits are completely untouched.
    const doc = await firestore.getCategory('furniture');
    assert.equal(doc.name, 'Renamed By Admin');
    assert.equal(doc.isActive, false);
    assert.equal(doc.sortOrder, 999);
  });

  it('does not re-upload when the same-content object already exists in Storage', async () => {
    const firestore = new FakeFirestoreAdapter();
    const storage = new FakeStorageAdapter();

    const first = await seedOneCategory(entry('rugs'), {
      repoRoot,
      firestoreAdapter: firestore,
      storageAdapter: storage,
      force: false,
    });
    assert.equal(storage.uploadCallCount, 1);

    // Simulate a rerun where the document doesn't exist yet (e.g. a prior
    // run's Firestore write hadn't happened) but the Storage object from
    // that prior attempt persists.
    const firestore2 = new FakeFirestoreAdapter();
    const second = await seedOneCategory(entry('rugs'), {
      repoRoot,
      firestoreAdapter: firestore2,
      storageAdapter: storage,
      force: false,
    });

    assert.equal(second.ok, true);
    assert.equal(storage.uploadCallCount, 1); // still only ever uploaded once
    assert.equal(first.imageUrl, second.imageUrl);
  });

  it('--force overwrites an existing document back to canonical values', async () => {
    const firestore = new FakeFirestoreAdapter({
      decor: {
        name: 'Renamed By Admin',
        key: 'decor',
        kind: 'decor',
        imageUrl: 'https://already.example/admin-uploaded.png',
        isActive: false,
        sortOrder: 999,
      },
    });
    const storage = new FakeStorageAdapter();
    const result = await seedOneCategory(entry('decor'), {
      repoRoot,
      firestoreAdapter: firestore,
      storageAdapter: storage,
      force: true,
    });

    assert.equal(result.ok, true);
    assert.equal(result.skipped, false);
    assert.equal(result.forced, true);
    const doc = await firestore.getCategory('decor');
    assert.equal(doc.name, 'Decor');
    assert.equal(doc.isActive, true);
    assert.equal(doc.sortOrder, 10);
  });
});

describe('seedOneCategory — rollback on Firestore failure', () => {
  it('rolls back only the newly uploaded object when the document create fails', async () => {
    const firestore = new FakeFirestoreAdapter();
    firestore.failCreateFor.add('lighting');
    const storage = new FakeStorageAdapter();

    const result = await seedOneCategory(entry('lighting'), {
      repoRoot,
      firestoreAdapter: firestore,
      storageAdapter: storage,
      force: false,
    });

    assert.equal(result.ok, false);
    assert.equal(storage.deleteCalls.length, 1);
    assert.equal(storage.objects.size, 0);
    assert.equal(await firestore.getCategory('lighting'), null);
  });
});

describe('runSeed — per-entry independence', () => {
  it('one failing entry does not block the others from succeeding', async () => {
    const firestore = new FakeFirestoreAdapter();
    const storage = new FakeStorageAdapter();
    const entries = [
      entry('furniture'),
      entry('clothing', {
        sourceImageAssetPath: 'assets/images/home/categories/does-not-exist.png',
      }),
      entry('rugs'),
    ];

    const results = await runSeed(entries, {
      repoRoot,
      firestoreAdapter: firestore,
      storageAdapter: storage,
      force: false,
    });

    assert.deepEqual(
      results.map((r) => [r.key, r.ok]),
      [
        ['furniture', true],
        ['clothing', false],
        ['rugs', true],
      ],
    );
  });
});

describe('project guard', () => {
  it('refuses with no project id', () => {
    assert.throws(() => assertProjectGuard(null), /Refusing to run live writes/);
  });
  it('refuses with the wrong project id', () => {
    assert.throws(() => assertProjectGuard('wrong'), /Refusing to run live writes/);
  });
  it('allows the exact confirmed project id', () => {
    assert.doesNotThrow(() => assertProjectGuard(CONFIRMED_PROJECT_ID));
  });
});
