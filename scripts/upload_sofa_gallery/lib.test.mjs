// Unit tests for the Phase 9.2 R14 Stage A sofa-gallery uploader.
// `node --test lib.test.mjs` — no live Firebase needed.

import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import {
  applyUpload,
  assertProjectGuard,
  buildUploadPlan,
  preflightDestination,
} from './lib.mjs';
import {
  SOFA_GALLERY,
  imageRefFor,
  md5Base64,
  objectPathFor,
  preflightSource,
  publicUrlFor,
  sofaImageFields,
} from './sofa_gallery.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');

test('project guard', () => {
  assert.doesNotThrow(() => assertProjectGuard('dry-run', null));
  assert.throws(() => assertProjectGuard('apply', 'other'));
  assert.doesNotThrow(() => assertProjectGuard('apply', 'twin-ar-d4d75'));
});

test('SOFA_GALLERY: six renders, one main, content-hashed paths', () => {
  assert.equal(SOFA_GALLERY.length, 6);
  assert.equal(SOFA_GALLERY.filter((i) => i.role === 'main').length, 1);
  const orders = SOFA_GALLERY.map((i) => i.order).sort((a, b) => a - b);
  assert.deepEqual(orders, [0, 1, 2, 3, 4, 5]);
  for (const item of SOFA_GALLERY) {
    assert.match(item.expectedSha256, /^[0-9a-f]{64}$/);
    assert.equal(objectPathFor(item), `products/luna-3-seater-sofa/images/${item.stableName}`);
    assert.match(item.stableName, /^img-[0-9a-f]{16}\.png$/);
    // the stable name is derived from the sha256 (Phase 8.7.1 convention)
    assert.equal(item.stableName, `img-${item.expectedSha256.slice(0, 16)}.png`);
  }
});

test('preflightSource verifies the real renders on disk (SHA-256 + size exact)', () => {
  for (const item of SOFA_GALLERY) {
    const r = preflightSource(WORKSPACE_ROOT, item);
    assert.equal(r.ok, true, `${item.sourceRelPath}: ${r.reason ?? ''}`);
    assert.equal(r.sha256, item.expectedSha256);
    assert.equal(r.sizeBytes, item.expectedSizeBytes);
  }
});

test('preflightSource rejects a hash/size mismatch', () => {
  const bad = { ...SOFA_GALLERY[0], expectedSha256: 'f'.repeat(64) };
  const r = preflightSource(WORKSPACE_ROOT, bad);
  assert.equal(r.ok, false);
  assert.match(r.reason, /SHA-256 mismatch/);

  const badSize = { ...SOFA_GALLERY[0], expectedSizeBytes: 1 };
  assert.match(preflightSource(WORKSPACE_ROOT, badSize).reason, /size .* != expected 1/);
});

test('sofaImageFields: mainImage = the cat_3q render, gallery in order', () => {
  const { mainImage, galleryMedia } = sofaImageFields();
  assert.equal(mainImage.source, 'network');
  assert.match(mainImage.path, /firebasestorage\.googleapis\.com/);
  assert.equal(mainImage.path, publicUrlFor(SOFA_GALLERY.find((i) => i.role === 'main')));
  assert.equal(galleryMedia.length, 6);
  assert.deepEqual(galleryMedia[0], mainImage);
  assert.deepEqual(galleryMedia, SOFA_GALLERY.map(imageRefFor));
});

// ── destination classification ──────────────────────────────────────────────

const src = { ok: true, buffer: Buffer.from('x'), sizeBytes: 46000, sha256: 'z', md5: md5Base64(Buffer.from('x')) };

/** A fully-staged existing object: right bytes, right content type, AND the
 *  required custom sha256 metadata. */
const stagedMeta = {
  exists: true,
  md5Base64: src.md5,
  size: String(src.sizeBytes),
  contentType: 'image/png',
  sha256Meta: src.sha256,
  generation: '7',
};

test('preflightDestination: absent / identical / conflict', async () => {
  const item = SOFA_GALLERY[0];
  const absent = { async getMetadata() { return { exists: false }; } };
  assert.equal((await preflightDestination(absent, item, src)).state, 'absent');

  const identical = { async getMetadata() { return { ...stagedMeta }; } };
  assert.equal((await preflightDestination(identical, item, src)).state, 'identical');

  const diffBytes = {
    async getMetadata() {
      return { ...stagedMeta, md5Base64: 'OTHER==' };
    },
  };
  const c = await preflightDestination(diffBytes, item, src);
  assert.equal(c.state, 'conflict');
  assert.match(c.detail, /md5/);

  const noMd5 = { async getMetadata() { return { exists: true, md5Base64: null, size: String(src.sizeBytes) }; } };
  assert.equal((await preflightDestination(noMd5, item, src)).state, 'conflict');
});

test('preflightDestination: right bytes but missing the required sha256 metadata → conflict, no overwrite', async () => {
  const item = SOFA_GALLERY[0];
  const noShaMeta = {
    async getMetadata() {
      return { ...stagedMeta, sha256Meta: null };
    },
  };
  const c = await preflightDestination(noShaMeta, item, src);
  assert.equal(c.state, 'conflict');
  assert.match(c.detail, /missing required twinArSofaGallerySha256/);
  assert.match(c.detail, /will NOT overwrite/);

  const wrongShaMeta = {
    async getMetadata() {
      return { ...stagedMeta, sha256Meta: 'deadbeef' };
    },
  };
  assert.match((await preflightDestination(wrongShaMeta, item, src)).detail, /twinArSofaGallerySha256 deadbeef/);

  const noContentType = {
    async getMetadata() {
      return { ...stagedMeta, contentType: null };
    },
  };
  assert.match((await preflightDestination(noContentType, item, src)).detail, /no content type/);
});

// ── plan + apply ────────────────────────────────────────────────────────────

function fakeStorage(objects = {}) {
  const store = new Map(Object.entries(objects));
  return {
    uploads: [],
    async getMetadata(p) {
      const o = store.get(p);
      return o ? { exists: true, ...o } : { exists: false };
    },
    async upload(p, buffer, opts) {
      if (opts.ifGenerationMatch === 0 && store.has(p)) {
        throw new Error('precondition failed: object exists');
      }
      store.set(p, {
        md5Base64: md5Base64(buffer),
        size: buffer.length,
        contentType: opts.contentType,
        sha256Meta: opts.metadata?.twinArSofaGallerySha256 ?? null,
        generation: String(Date.now()),
      });
      this.uploads.push({ p, opts });
      return { generation: '1' };
    },
    _store: store,
  };
}

test('buildUploadPlan: all absent → six uploads, no abort', async () => {
  const plan = await buildUploadPlan(fakeStorage(), WORKSPACE_ROOT);
  assert.equal(plan.abort, false);
  assert.equal(plan.toCreateCount, 6);
});

test('applyUpload uploads absent objects create-only; a conflict aborts the run', async () => {
  const storage = fakeStorage();
  const plan = await buildUploadPlan(storage, WORKSPACE_ROOT);
  const report = await applyUpload(plan, storage);
  assert.equal(report.created.length, 6);
  assert.equal(report.failed.length, 0);
  assert.ok(storage.uploads.every((u) => u.opts.ifGenerationMatch === 0));
  assert.equal(report.rollbackInventory.length, 6);

  // re-run → all identical, skipped
  const plan2 = await buildUploadPlan(storage, WORKSPACE_ROOT);
  assert.equal(plan2.toSkipCount, 6);
  const report2 = await applyUpload(plan2, storage);
  assert.equal(report2.created.length, 0);
  assert.equal(report2.skipped.length, 6);

  // a byte-different existing object blocks the whole run
  const dirty = fakeStorage({
    [objectPathFor(SOFA_GALLERY[0])]: { md5Base64: 'WRONG==', size: 10, contentType: 'image/png', generation: '1' },
  });
  const plan3 = await buildUploadPlan(dirty, WORKSPACE_ROOT);
  assert.equal(plan3.abort, true);
  await assert.rejects(() => applyUpload(plan3, dirty), /aborting plan/);
  assert.equal(dirty.uploads.length, 0);
});
