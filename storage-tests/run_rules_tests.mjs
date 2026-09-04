// Firebase Storage Security Rules verification for TWin AR Phase 8.7
// (`products/{productId}/images/{imageId}`, `users/{uid}/profile/{imageId}`)
// and Phase 8.8 (`categories/{categoryId}/images/{imageId}`).
// Runs against the real Storage emulator - full fidelity for content-type/
// size checks and the owner+admin-only avatar read boundary, which no
// in-`flutter test` fake can evaluate. Invoked via `npm test` here, which
// wraps this script in `firebase emulators:exec`. Not part of the Flutter
// build/app runtime - mirrors `../firestore-tests/` exactly, per
// `13_TESTING_AND_QA_RULES.md`'s Lean Testing Policy.

import { readFileSync } from 'fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

const ALICE = 'alice-uid';
const BOB = 'bob-uid';
const ADMIN = 'admin-uid';

// A minimal but real JPEG magic-number prefix, padded out - content-type is
// asserted from the upload metadata by the rules (`request.resource
// .contentType`), not by sniffing bytes, but real-shaped bytes keep this
// honest or the emulator's own transport layer.
const jpegBytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
const oversizedProductImageBytes = new Uint8Array(11 * 1024 * 1024); // > 10MB
const oversizedAvatarBytes = new Uint8Array(3 * 1024 * 1024); // > 2MB
const oversizedCategoryImageBytes = new Uint8Array(6 * 1024 * 1024); // > 5MB (Phase 8.8)

// Phase 9.2 R10 — a real GLB magic-number prefix ("glTF" + version 2). The
// rules gate on `request.resource.contentType` / path shape / size, not byte
// content, but real-shaped bytes keep the emulator transport honest.
const glbBytes = new Uint8Array([0x67, 0x6c, 0x54, 0x46, 2, 0, 0, 0]);
const oversizedArModelBytes = new Uint8Array(13 * 1024 * 1024); // > 12MB

// Phase 9.2 R16 — the `twinArAr*` provenance every AR-model write must carry
// (`hasArModelProvenance()`): a 64-hex SHA-256 + a numeric version. Same shape
// the Admin app and `scripts/upload_ar_models/` both write.
const arModelProvenance = {
  twinArArModelSha256: 'a'.repeat(64),
  twinArArModelVersion: '1',
  twinArArWidthM: '0.7',
  twinArArDepthM: '0.72',
  twinArArHeightM: '0.82',
  twinArArScaleContract: 'twin-ar/scale-contract-9.2.2',
};
const arModelWriteMeta = (contentType = 'model/gltf-binary') => ({
  contentType,
  customMetadata: arModelProvenance,
});

let testEnv;
const results = [];

async function run(name, fn) {
  try {
    await fn();
    results.push({ name, pass: true });
    console.log(`  PASS - ${name}`);
  } catch (err) {
    results.push({ name, pass: false, err });
    console.error(`  FAIL - ${name}`);
    console.error(`    ${err.message}`);
  }
}

function storageFor(uid, tokenOptions) {
  const context = uid
    ? testEnv.authenticatedContext(uid, tokenOptions)
    : testEnv.unauthenticatedContext();
  return context.storage();
}

async function seed(path, bytes = jpegBytes, contentType = 'image/jpeg') {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(ref(context.storage(), path), bytes, { contentType });
  });
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-twin-ar-storage-rules-test',
    storage: {
      rules: readFileSync('../storage.rules', 'utf8'),
      host: 'localhost',
      port: 9199,
    },
  });

  console.log('products/{productId}/images/{imageId} - read');

  await run('an unauthenticated client can read a product image (public read)', async () => {
    await seed('products/p1/images/a.jpg');
    const anon = storageFor(null);
    await assertSucceeds(getBytes(ref(anon, 'products/p1/images/a.jpg')));
  });

  await run('a signed-in customer can read a product image', async () => {
    await seed('products/p2/images/a.jpg');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(getBytes(ref(alice, 'products/p2/images/a.jpg')));
  });

  console.log('products/{productId}/images/{imageId} - write');

  await run('a superAdmin can upload a valid product image', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      uploadBytes(ref(admin, 'products/p3/images/b.jpg'), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  await run('a customer cannot upload a product image', async () => {
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      uploadBytes(ref(alice, 'products/p4/images/c.jpg'), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  await run('an unauthenticated client cannot upload a product image', async () => {
    const anon = storageFor(null);
    await assertFails(
      uploadBytes(ref(anon, 'products/p5/images/d.jpg'), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  await run('a superAdmin upload is rejected for a non-image content type', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(ref(admin, 'products/p6/images/e.pdf'), jpegBytes, {
        contentType: 'application/pdf',
      }),
    );
  });

  await run('a superAdmin upload is rejected over the 10MB product-image limit', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/p7/images/big.jpg'),
        oversizedProductImageBytes,
        { contentType: 'image/jpeg' },
      ),
    );
  });

  await run('a superAdmin can update (overwrite) an existing product image', async () => {
    await seed('products/p8/images/f.jpg');
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      uploadBytes(ref(admin, 'products/p8/images/f.jpg'), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  console.log('products/{productId}/images/{imageId} - delete');

  await run('a superAdmin can delete a product image', async () => {
    await seed('products/p9/images/g.jpg');
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(deleteObject(ref(admin, 'products/p9/images/g.jpg')));
  });

  await run('a customer cannot delete a product image', async () => {
    await seed('products/p10/images/h.jpg');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(deleteObject(ref(alice, 'products/p10/images/h.jpg')));
  });

  await run('an unauthenticated client cannot delete a product image', async () => {
    await seed('products/p11/images/i.jpg');
    const anon = storageFor(null);
    await assertFails(deleteObject(ref(anon, 'products/p11/images/i.jpg')));
  });

  console.log('users/{uid}/profile/{imageId} - write (owner-only)');

  await run('the owner can upload their own avatar', async () => {
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(
      uploadBytes(ref(alice, `users/${ALICE}/profile/avatar.jpg`), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  await run("a different signed-in user cannot write to another user's avatar path - core write isolation", async () => {
    const bob = storageFor(BOB, { role: 'customer' });
    await assertFails(
      uploadBytes(ref(bob, `users/${ALICE}/profile/hijack.jpg`), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  await run('an unauthenticated client cannot upload any avatar', async () => {
    const anon = storageFor(null);
    await assertFails(
      uploadBytes(ref(anon, `users/${ALICE}/profile/anon.jpg`), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  await run("a superAdmin CANNOT write to a customer's avatar path - read-only admin access, never write", async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, `users/${ALICE}/profile/admin-write.jpg`),
        jpegBytes,
        { contentType: 'image/jpeg' },
      ),
    );
  });

  await run('avatar upload is rejected for a non-image content type', async () => {
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      uploadBytes(ref(alice, `users/${ALICE}/profile/doc.pdf`), jpegBytes, {
        contentType: 'application/pdf',
      }),
    );
  });

  await run('avatar upload is rejected over the 2MB avatar limit', async () => {
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      uploadBytes(
        ref(alice, `users/${ALICE}/profile/big.jpg`),
        oversizedAvatarBytes,
        { contentType: 'image/jpeg' },
      ),
    );
  });

  await run('the owner can update (replace) their own avatar', async () => {
    await seed(`users/${ALICE}/profile/replace.jpg`);
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(
      uploadBytes(ref(alice, `users/${ALICE}/profile/replace.jpg`), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  console.log('users/{uid}/profile/{imageId} - read (owner + admin only)');

  await run('the owner can read their own avatar', async () => {
    await seed(`users/${ALICE}/profile/read.jpg`);
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(getBytes(ref(alice, `users/${ALICE}/profile/read.jpg`)));
  });

  await run("a different signed-in user CANNOT read another user's avatar - the core read-isolation guarantee (User 2 must never see User 1's avatar)", async () => {
    await seed(`users/${ALICE}/profile/private.jpg`);
    const bob = storageFor(BOB, { role: 'customer' });
    await assertFails(getBytes(ref(bob, `users/${ALICE}/profile/private.jpg`)));
  });

  await run('an unauthenticated client cannot read any avatar (not public, unlike product images)', async () => {
    await seed(`users/${ALICE}/profile/anon-read.jpg`);
    const anon = storageFor(null);
    await assertFails(getBytes(ref(anon, `users/${ALICE}/profile/anon-read.jpg`)));
  });

  await run("a superAdmin can read any customer's avatar", async () => {
    await seed(`users/${ALICE}/profile/admin-read.jpg`);
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      getBytes(ref(admin, `users/${ALICE}/profile/admin-read.jpg`)),
    );
  });

  console.log('users/{uid}/profile/{imageId} - delete');

  await run('the owner can delete their own avatar (replace/rollback path)', async () => {
    await seed(`users/${ALICE}/profile/delete-me.jpg`);
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(
      deleteObject(ref(alice, `users/${ALICE}/profile/delete-me.jpg`)),
    );
  });

  await run("a different user cannot delete another user's avatar", async () => {
    await seed(`users/${ALICE}/profile/protected.jpg`);
    const bob = storageFor(BOB, { role: 'customer' });
    await assertFails(
      deleteObject(ref(bob, `users/${ALICE}/profile/protected.jpg`)),
    );
  });

  await run(
    "a superAdmin CANNOT delete a customer's avatar - admin access to avatars stays read-only, never write or delete",
    async () => {
      await seed(`users/${ALICE}/profile/admin-cannot-delete.jpg`);
      const admin = storageFor(ADMIN, { role: 'superAdmin' });
      await assertFails(
        deleteObject(ref(admin, `users/${ALICE}/profile/admin-cannot-delete.jpg`)),
      );
    },
  );

  console.log('categories/{categoryId}/images/{imageId} - read (Phase 8.8)');

  await run('an unauthenticated client can read a category image (public read)', async () => {
    await seed('categories/furniture/images/a.jpg');
    const anon = storageFor(null);
    await assertSucceeds(getBytes(ref(anon, 'categories/furniture/images/a.jpg')));
  });

  await run('a signed-in customer can read a category image', async () => {
    await seed('categories/clothing/images/a.jpg');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(getBytes(ref(alice, 'categories/clothing/images/a.jpg')));
  });

  console.log('categories/{categoryId}/images/{imageId} - write (Phase 8.8)');

  await run('a superAdmin can upload a valid category image', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      uploadBytes(ref(admin, 'categories/rugs/images/b.jpg'), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  await run('a customer cannot upload a category image', async () => {
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      uploadBytes(ref(alice, 'categories/decor/images/c.jpg'), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  await run('an unauthenticated client cannot upload a category image', async () => {
    const anon = storageFor(null);
    await assertFails(
      uploadBytes(ref(anon, 'categories/lighting/images/d.jpg'), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  await run('a superAdmin upload is rejected for a non-image content type', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(ref(admin, 'categories/furniture/images/e.pdf'), jpegBytes, {
        contentType: 'application/pdf',
      }),
    );
  });

  await run('a superAdmin upload is rejected over the 5MB category-image limit', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'categories/furniture/images/big.jpg'),
        oversizedCategoryImageBytes,
        { contentType: 'image/jpeg' },
      ),
    );
  });

  await run('a superAdmin can update (overwrite/replace) an existing category image', async () => {
    await seed('categories/furniture/images/f.jpg');
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      uploadBytes(ref(admin, 'categories/furniture/images/f.jpg'), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  console.log('categories/{categoryId}/images/{imageId} - delete (Phase 8.8)');

  await run('a superAdmin can delete a category image', async () => {
    await seed('categories/furniture/images/g.jpg');
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(deleteObject(ref(admin, 'categories/furniture/images/g.jpg')));
  });

  await run('a customer cannot delete a category image', async () => {
    await seed('categories/furniture/images/h.jpg');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(deleteObject(ref(alice, 'categories/furniture/images/h.jpg')));
  });

  await run('an unauthenticated client cannot delete a category image', async () => {
    await seed('categories/furniture/images/i.jpg');
    const anon = storageFor(null);
    await assertFails(deleteObject(ref(anon, 'categories/furniture/images/i.jpg')));
  });

  console.log('products/{productId}/ar/model-v{n}.glb — read (Phase 9.2 R10)');

  await run('a signed-in customer can read an approved product AR model', async () => {
    await seed(
      'products/luna-accent-chair/ar/model-v1.glb',
      glbBytes,
      'model/gltf-binary',
    );
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(
      getBytes(ref(alice, 'products/luna-accent-chair/ar/model-v1.glb')),
    );
  });

  await run('an unauthenticated client CANNOT read an AR model (not public, unlike product images)', async () => {
    await seed(
      'products/glass-coffee-table/ar/model-v1.glb',
      glbBytes,
      'model/gltf-binary',
    );
    const anon = storageFor(null);
    await assertFails(
      getBytes(ref(anon, 'products/glass-coffee-table/ar/model-v1.glb')),
    );
  });

  await run('a signed-in customer cannot read a non-approved product AR model', async () => {
    await seed(
      'products/velvet-armchair/ar/model-v1.glb',
      glbBytes,
      'model/gltf-binary',
    );
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      getBytes(ref(alice, 'products/velvet-armchair/ar/model-v1.glb')),
    );
  });

  await run('a superAdmin CAN read a non-approved product AR model (Phase 9.2 R16 — needed for the Admin AR & Media preview/re-verify; a superset of the write privilege they already hold)', async () => {
    await seed(
      'products/velvet-armchair/ar/model-v2.glb',
      glbBytes,
      'model/gltf-binary',
    );
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      getBytes(ref(admin, 'products/velvet-armchair/ar/model-v2.glb')),
    );
  });

  await run('a superAdmin still cannot read a wrongly-named object under ar/', async () => {
    await seed(
      'products/velvet-armchair/ar/latest.glb',
      glbBytes,
      'model/gltf-binary',
    );
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      getBytes(ref(admin, 'products/velvet-armchair/ar/latest.glb')),
    );
  });

  await run('a signed-in customer cannot read a wrongly-named object under ar/', async () => {
    await seed(
      'products/luna-accent-chair/ar/model.glb',
      glbBytes,
      'model/gltf-binary',
    );
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      getBytes(ref(alice, 'products/luna-accent-chair/ar/model.glb')),
    );
  });

  console.log('products/{productId}/ar/model-v{n}.glb — write (Phase 9.2 R10)');

  await run('a superAdmin can upload a valid AR model (model/gltf-binary + provenance)', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      uploadBytes(
        ref(admin, 'products/luna-accent-chair/ar/model-v1.glb'),
        glbBytes,
        arModelWriteMeta('model/gltf-binary'),
      ),
    );
  });

  await run('a superAdmin can upload a valid AR model (application/octet-stream + provenance)', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      uploadBytes(
        ref(admin, 'products/modern-table-lamp/ar/model-v1.glb'),
        glbBytes,
        arModelWriteMeta('application/octet-stream'),
      ),
    );
  });

  await run('a superAdmin AR-model upload is rejected with NO twinArAr* provenance (Phase 9.2 R16)', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/luna-accent-chair/ar/model-v1.glb'),
        glbBytes,
        { contentType: 'model/gltf-binary' },
      ),
    );
  });

  await run('a superAdmin AR-model upload is rejected for a malformed SHA-256 in provenance', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/luna-accent-chair/ar/model-v1.glb'),
        glbBytes,
        {
          contentType: 'model/gltf-binary',
          customMetadata: { ...arModelProvenance, twinArArModelSha256: 'NOTHEX' },
        },
      ),
    );
  });

  await run('a customer cannot upload an AR model', async () => {
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      uploadBytes(
        ref(alice, 'products/luna-accent-chair/ar/model-v1.glb'),
        glbBytes,
        { contentType: 'model/gltf-binary' },
      ),
    );
  });

  await run('an unauthenticated client cannot upload an AR model', async () => {
    const anon = storageFor(null);
    await assertFails(
      uploadBytes(
        ref(anon, 'products/luna-accent-chair/ar/model-v1.glb'),
        glbBytes,
        { contentType: 'model/gltf-binary' },
      ),
    );
  });

  await run('a superAdmin AR-model upload is rejected for a non-GLB content type', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/luna-accent-chair/ar/model-v1.glb'),
        glbBytes,
        arModelWriteMeta('image/png'),
      ),
    );
  });

  await run('a superAdmin AR-model upload is rejected over the 12MB limit', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/luna-accent-chair/ar/model-v1.glb'),
        oversizedArModelBytes,
        arModelWriteMeta(),
      ),
    );
  });

  await run('a superAdmin AR-model upload is rejected for a wrong extension', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/luna-accent-chair/ar/model-v1.gltf'),
        glbBytes,
        arModelWriteMeta(),
      ),
    );
  });

  await run('a superAdmin AR-model upload is rejected for an unversioned name', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/luna-accent-chair/ar/model.glb'),
        glbBytes,
        arModelWriteMeta(),
      ),
    );
  });

  await run('a superAdmin cannot write under a deeper ar/ sub-path', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/luna-accent-chair/ar/archive/model-v1.glb'),
        glbBytes,
        arModelWriteMeta(),
      ),
    );
  });

  console.log('products/{productId}/ar/model-v{n}.glb — delete (Phase 9.2 R10)');

  await run('a superAdmin can delete an AR model', async () => {
    await seed(
      'products/luna-3-seater-sofa/ar/model-v1.glb',
      glbBytes,
      'model/gltf-binary',
    );
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      deleteObject(ref(admin, 'products/luna-3-seater-sofa/ar/model-v1.glb')),
    );
  });

  await run('a customer cannot delete an AR model', async () => {
    await seed(
      'products/luna-3-seater-sofa/ar/model-v1.glb',
      glbBytes,
      'model/gltf-binary',
    );
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      deleteObject(ref(alice, 'products/luna-3-seater-sofa/ar/model-v1.glb')),
    );
  });

  console.log('catch-all');

  await run('every other path is denied to everyone, including a superAdmin', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(ref(admin, 'random/path/x.jpg'), jpegBytes, {
        contentType: 'image/jpeg',
      }),
    );
  });

  await run('an unauthenticated client is denied on an unknown path', async () => {
    const anon = storageFor(null);
    await assertFails(getBytes(ref(anon, 'random/path/x.jpg')));
  });

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} passed.`);
  if (failed.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
