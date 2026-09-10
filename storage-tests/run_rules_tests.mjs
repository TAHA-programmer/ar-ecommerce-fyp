// Firebase Storage Security Rules verification for TWin AR Phase 8.7
// (`products/{productId}/images/{imageId}`, `users/{uid}/profile/{imageId}`)
// and Phase 8.8 (`categories/{categoryId}/images/{imageId}`).
// Runs against the real Storage emulator - full fidelity for content-type/
// size checks and the owner+admin-only avatar read boundary, which no
// in-`flutter test` fake can evaluate. Invoked via `npm test` here, which
// wraps this script in `firebase emulators:exec`. Not part of the Flutter
// build/app runtime - mirrors `../firestore-tests/` exactly, per
// `13_TESTING_AND_QA_RULES.md`'s Lean Testing Policy.
//
// Phase 9.2 §17-follow-up: the `products/{productId}/ar/{modelFile}` READ
// rule is now metadata-driven — it cross-service-reads the product's own
// live `products/{productId}` Firestore document (`firestore.get()` /
// `firestore.exists()` from within a Storage rule). Proving that requires
// BOTH emulators running together (`--only firestore,storage`, both already
// declared in `../firebase.json`) and this suite now seeds Firestore
// product documents (bypassing Firestore's own rules, exactly like the
// existing Storage `seed()` helper bypasses Storage's) before exercising
// Storage reads against them.

import { readFileSync } from 'fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';
import { doc, setDoc, deleteDoc } from 'firebase/firestore';

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

// Phase 9.3 Stage 3 - the `twinArVto*` provenance every VTO garment-image
// write must carry (`hasVtoGarmentProvenance()`): a 64-hex SHA-256 + numeric
// version.
const pngBytes = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const oversizedVtoGarmentBytes = new Uint8Array(13 * 1024 * 1024); // > 12MB
const vtoGarmentProvenance = {
  twinArVtoSha256: 'a'.repeat(64),
  twinArVtoVersion: '1',
  twinArVtoWidth: '900',
  twinArVtoHeight: '1200',
  twinArVtoContentType: 'image/png',
};
const vtoWriteMeta = (contentType = 'image/png') => ({
  contentType,
  customMetadata: vtoGarmentProvenance,
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

// Phase 9.2 §17-follow-up — the exact `ar*` shape `hasRenderableArMetadata()`
// requires, ready for a customer read of `products/{productId}/ar/model-v1
// .glb`. Every field mirrors `ProductArMetadata.toFirestoreFields()`.
function validArProductDoc(productId, overrides = {}) {
  return {
    publicationStatus: 'published',
    isActive: true,
    experienceType: 'roomAr',
    arModelStoragePath: `products/${productId}/ar/model-v1.glb`,
    arModelFormat: 'glb',
    arModelVersion: '1',
    arModelSha256: 'a'.repeat(64),
    arWidthM: 0.7,
    arDepthM: 0.72,
    arHeightM: 0.82,
    arScale: 1.0,
    arScaleContract: 'twin-ar/scale-contract-9.2.2',
    ...overrides,
  };
}

// Bypasses firestore.rules, exactly like `seed()` bypasses storage.rules —
// this is the developer/Admin-SDK write path in production (the app itself
// only ever gets here through `isAdmin()`-gated writes).
async function seedProduct(productId, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'products', productId), data);
  });
}

async function deleteProductDoc(productId) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), 'products', productId));
  });
}

async function main() {
  testEnv = await initializeTestEnvironment({
    // Must match the project the emulator suite is actually configured for
    // (`.firebaserc` / `firebase.json`'s `flutter.platforms` block —
    // `twin-ar-d4d75`), NOT an arbitrary "demo-" label. The emulator suite
    // defaults to "single project mode": a Storage rule's cross-service
    // `firestore.get()` call is routed to THAT configured project
    // regardless of what project id a client SDK requests, so seeding a
    // Firestore document under a different project id (as this test
    // originally did) leaves the Storage rule looking at an empty
    // namespace — confirmed directly via the emulator's own log
    // ("Multiple projectIds are not recommended in single project mode…").
    // Still fully local — this never reaches any real Firebase project.
    projectId: 'twin-ar-d4d75',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: 'localhost',
      port: 8080,
    },
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

  console.log('products/{productId}/ar/model-v{n}.glb — read, metadata-driven (Phase 9.2 §17-follow-up)');

  await run('a signed-in customer can read an original-four product AR model whose Firestore doc is complete + matching', async () => {
    await seedProduct('luna-accent-chair', validArProductDoc('luna-accent-chair', {
      arWidthM: 0.70, arDepthM: 0.72, arHeightM: 0.82,
      arModelSha256: 'd67c68f823d06881ec1aabf7f8ca6f0128f1016483ea0307f5c2ecef66b3cf94',
    }));
    await seed('products/luna-accent-chair/ar/model-v1.glb', glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(
      getBytes(ref(alice, 'products/luna-accent-chair/ar/model-v1.glb')),
    );
  });

  await run('a signed-in customer can read a Phase 9.2 coverage-expansion product (velvet-armchair) with no hardcoded allowlist entry', async () => {
    await seedProduct('velvet-armchair', validArProductDoc('velvet-armchair', {
      arWidthM: 0.72, arDepthM: 0.76, arHeightM: 0.78,
      arModelSha256: '9909929fdc84adf526127887ab782805bee0ff6863c04e0dd1510a4264f8a09e',
    }));
    await seed('products/velvet-armchair/ar/model-v1.glb', glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(
      getBytes(ref(alice, 'products/velvet-armchair/ar/model-v1.glb')),
    );
  });

  await run('a signed-in customer can read a completely NEW, never-before-seen Admin-created product id — no manifest, enum, or rules edit involved', async () => {
    const id = 'future-admin-product-2026-09-05';
    await seedProduct(id, validArProductDoc(id));
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
  });

  await run('an unauthenticated client CANNOT read an AR model even with a fully valid Firestore doc (not public, unlike product images)', async () => {
    await seedProduct('glass-coffee-table', validArProductDoc('glass-coffee-table'));
    await seed('products/glass-coffee-table/ar/model-v1.glb', glbBytes, 'model/gltf-binary');
    const anon = storageFor(null);
    await assertFails(
      getBytes(ref(anon, 'products/glass-coffee-table/ar/model-v1.glb')),
    );
  });

  await run('a signed-in customer cannot read a product with NO Firestore document at all (missing metadata)', async () => {
    await seed('products/minimalist-bedroom-set/ar/model-v1.glb', glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      getBytes(ref(alice, 'products/minimalist-bedroom-set/ar/model-v1.glb')),
    );
  });

  await run('a signed-in customer cannot read when the Firestore doc is missing required ar* fields (malformed metadata)', async () => {
    const id = 'malformed-ar-product';
    await seedProduct(id, {
      publicationStatus: 'published',
      isActive: true,
      experienceType: 'roomAr',
      arModelStoragePath: `products/${id}/ar/model-v1.glb`,
      // arModelFormat / sha256 / dims / scale-contract all absent
    });
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
  });

  await run('a signed-in customer cannot read when arModelSha256 is malformed (not 64 lowercase hex)', async () => {
    const id = 'bad-sha-product';
    await seedProduct(id, validArProductDoc(id, { arModelSha256: 'NOT-HEX' }));
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
  });

  await run('a signed-in customer cannot read a disabled product (arModelDisabled: true)', async () => {
    const id = 'disabled-ar-product';
    await seedProduct(id, validArProductDoc(id, { arModelDisabled: true }));
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
  });

  await run('a signed-in customer cannot read an unpublished/hidden product (publicationStatus: draft)', async () => {
    const id = 'draft-ar-product';
    await seedProduct(id, validArProductDoc(id, { publicationStatus: 'draft' }));
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
  });

  await run('a signed-in customer cannot read an inactive product (isActive: false)', async () => {
    const id = 'inactive-ar-product';
    await seedProduct(id, validArProductDoc(id, { isActive: false }));
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
  });

  await run('a signed-in customer cannot read a non-roomAr product (experienceType: none)', async () => {
    const id = 'not-room-ar-product';
    await seedProduct(id, validArProductDoc(id, { experienceType: 'none' }));
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
  });

  await run('a signed-in customer cannot read a cross-product path — product A\'s own doc must name product A\'s object, not product B\'s', async () => {
    // product-a's Firestore doc (incorrectly / maliciously) claims product-b's object.
    await seedProduct('cross-product-a', validArProductDoc('cross-product-a', {
      arModelStoragePath: 'products/cross-product-b/ar/model-v1.glb',
    }));
    await seed('products/cross-product-a/ar/model-v1.glb', glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    // Reading product-a's own object: doc's path doesn't match product-a's own path.
    await assertFails(getBytes(ref(alice, 'products/cross-product-a/ar/model-v1.glb')));
    // Reading product-b's object directly: product-b has no doc of its own.
    await seed('products/cross-product-b/ar/model-v1.glb', glbBytes, 'model/gltf-binary');
    await assertFails(getBytes(ref(alice, 'products/cross-product-b/ar/model-v1.glb')));
  });

  await run('exact per-product path ownership: a stale v1 object is denied once the doc points at v2', async () => {
    const id = 'versioned-ar-product';
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    await seed(`products/${id}/ar/model-v2.glb`, glbBytes, 'model/gltf-binary');
    await seedProduct(id, validArProductDoc(id, {
      arModelStoragePath: `products/${id}/ar/model-v2.glb`,
      arModelVersion: '2',
    }));
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(getBytes(ref(alice, `products/${id}/ar/model-v2.glb`)));
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
  });

  await run('deleting the Firestore doc revokes customer read of the still-present Storage object', async () => {
    const id = 'deleted-doc-ar-product';
    await seedProduct(id, validArProductDoc(id));
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
    await deleteProductDoc(id);
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
  });

  await run('a superAdmin CAN read any product\'s model regardless of Firestore state (R16 preview/re-verify — a superset of the write privilege they already hold)', async () => {
    // No Firestore doc at all for this product.
    await seed('products/no-doc-admin-preview/ar/model-v2.glb', glbBytes, 'model/gltf-binary');
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      getBytes(ref(admin, 'products/no-doc-admin-preview/ar/model-v2.glb')),
    );
  });

  await run('a superAdmin still cannot read a wrongly-named object under ar/', async () => {
    await seed('products/luna-accent-chair/ar/latest.glb', glbBytes, 'model/gltf-binary');
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(getBytes(ref(admin, 'products/luna-accent-chair/ar/latest.glb')));
  });

  await run('a signed-in customer cannot read a wrongly-named object under ar/, even with a fully valid doc', async () => {
    await seedProduct('luna-accent-chair', validArProductDoc('luna-accent-chair'));
    await seed('products/luna-accent-chair/ar/model.glb', glbBytes, 'model/gltf-binary');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      getBytes(ref(alice, 'products/luna-accent-chair/ar/model.glb')),
    );
  });

  console.log('products/{productId}/ar/model-v{n}.glb — Admin upload-before-save sequence (no circular Firestore dependency)');

  await run('an authorized Admin can upload a brand-new product\'s GLB BEFORE any Firestore document exists for it', async () => {
    const id = 'not-yet-saved-product';
    // Deliberately no seedProduct() call — this proves the write rule never
    // consults Firestore, so the real Admin flow (Storage upload happens
    // before the Firestore write) can never deadlock on itself.
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      uploadBytes(
        ref(admin, `products/${id}/ar/model-v1.glb`),
        glbBytes,
        arModelWriteMeta('model/gltf-binary'),
      ),
    );
  });

  await run('full sequence: Admin upload (no doc) → Firestore save/association → customer read succeeds', async () => {
    const id = 'full-sequence-product';
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    // 1) Admin uploads the model first — no Firestore doc exists yet.
    await assertSucceeds(
      uploadBytes(
        ref(admin, `products/${id}/ar/model-v1.glb`),
        glbBytes,
        arModelWriteMeta('model/gltf-binary'),
      ),
    );
    // A customer cannot read it yet — no metadata associates it.
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
    // 2) Admin saves the product, associating the uploaded object.
    await seedProduct(id, validArProductDoc(id));
    // 3) Now the customer can read the exact associated model.
    await assertSucceeds(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));
  });

  await run('replacement: Admin uploads v2, re-associates, and the customer now gets v2 — never v1', async () => {
    const id = 'replace-sequence-product';
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    await seedProduct(id, validArProductDoc(id));
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));

    // Admin uploads the replacement...
    await assertSucceeds(
      uploadBytes(
        ref(admin, `products/${id}/ar/model-v2.glb`),
        glbBytes,
        arModelWriteMeta('model/gltf-binary'),
      ),
    );
    // ...then re-associates the product with it.
    await seedProduct(id, validArProductDoc(id, {
      arModelStoragePath: `products/${id}/ar/model-v2.glb`,
      arModelVersion: '2',
    }));
    await assertSucceeds(getBytes(ref(alice, `products/${id}/ar/model-v2.glb`)));
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));

    // Admin then deletes the superseded v1 object (post-Firestore-write, per
    // the app's own ordering) — deletion itself is still admin-only,
    // Firestore-independent.
    await assertSucceeds(deleteObject(ref(admin, `products/${id}/ar/model-v1.glb`)));
    await assertFails(deleteObject(ref(alice, `products/${id}/ar/model-v2.glb`)));
  });

  await run('removal: disabling the entry point (arModelDisabled) revokes customer read without deleting the object', async () => {
    const id = 'disable-sequence-product';
    await seed(`products/${id}/ar/model-v1.glb`, glbBytes, 'model/gltf-binary');
    await seedProduct(id, validArProductDoc(id));
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));

    await seedProduct(id, validArProductDoc(id, { arModelDisabled: true }));
    await assertFails(getBytes(ref(alice, `products/${id}/ar/model-v1.glb`)));

    // The object itself is untouched — an admin can still read/re-enable.
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(getBytes(ref(admin, `products/${id}/ar/model-v1.glb`)));
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

  console.log('products/{productId}/vto/garment-{slot}-v{n}.{ext} — Phase 9.3 Stage 3');

  await run('a signed-in customer can read a garment image', async () => {
    await seed('products/oxford/vto/garment-black-v1.png', pngBytes, 'image/png');
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertSucceeds(
      getBytes(ref(alice, 'products/oxford/vto/garment-black-v1.png')),
    );
  });

  await run('an unauthenticated client CANNOT read a garment image (signed-in only, unlike product images)', async () => {
    await seed('products/oxford/vto/garment-blue-v1.png', pngBytes, 'image/png');
    const anon = storageFor(null);
    await assertFails(getBytes(ref(anon, 'products/oxford/vto/garment-blue-v1.png')));
  });

  await run('a superAdmin can upload a valid garment image (type + provenance + name + size)', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      uploadBytes(
        ref(admin, 'products/oxford/vto/garment-black-v2.png'),
        pngBytes,
        vtoWriteMeta('image/png'),
      ),
    );
  });

  await run('a superAdmin CANNOT overwrite an existing garment version (create-only, versioned objects are immutable)', async () => {
    // Seed an object at the exact path first (bypassing rules).
    await seed('products/oxford/vto/garment-blue-v7.png', pngBytes, 'image/png');
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/oxford/vto/garment-blue-v7.png'),
        pngBytes,
        vtoWriteMeta('image/png'),
      ),
    );
  });

  await run('a superAdmin CAN re-create a garment version after it was deleted (rollback-then-retry)', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await seed('products/oxford/vto/garment-blue-v8.png', pngBytes, 'image/png');
    await assertSucceeds(deleteObject(ref(admin, 'products/oxford/vto/garment-blue-v8.png')));
    await assertSucceeds(
      uploadBytes(
        ref(admin, 'products/oxford/vto/garment-blue-v8.png'),
        pngBytes,
        vtoWriteMeta('image/png'),
      ),
    );
  });

  await run('a superAdmin can upload a valid JPEG garment image', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertSucceeds(
      uploadBytes(
        ref(admin, 'products/oxford/vto/garment-default-v1.jpg'),
        jpegBytes,
        vtoWriteMeta('image/jpeg'),
      ),
    );
  });

  await run('a superAdmin garment upload is rejected with NO twinArVto* provenance', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/oxford/vto/garment-black-v3.png'),
        pngBytes,
        { contentType: 'image/png' },
      ),
    );
  });

  await run('a superAdmin garment upload is rejected for a malformed SHA-256 in provenance', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/oxford/vto/garment-black-v3.png'),
        pngBytes,
        { contentType: 'image/png', customMetadata: { ...vtoGarmentProvenance, twinArVtoSha256: 'NOTHEX' } },
      ),
    );
  });

  await run('a superAdmin garment upload is rejected for a non-image content type', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/oxford/vto/garment-black-v3.png'),
        pngBytes,
        vtoWriteMeta('model/gltf-binary'),
      ),
    );
  });

  await run('a superAdmin garment upload is rejected over the 12MB limit', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/oxford/vto/garment-black-v3.png'),
        oversizedVtoGarmentBytes,
        vtoWriteMeta('image/png'),
      ),
    );
  });

  await run('a superAdmin garment upload is rejected for a bad object name (no version)', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/oxford/vto/garment-black.png'),
        pngBytes,
        vtoWriteMeta('image/png'),
      ),
    );
  });

  await run('a superAdmin cannot write under a deeper vto/ sub-path', async () => {
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    await assertFails(
      uploadBytes(
        ref(admin, 'products/oxford/vto/archive/garment-black-v1.png'),
        pngBytes,
        vtoWriteMeta('image/png'),
      ),
    );
  });

  await run('a customer cannot upload a garment image', async () => {
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(
      uploadBytes(
        ref(alice, 'products/oxford/vto/garment-black-v9.png'),
        pngBytes,
        vtoWriteMeta('image/png'),
      ),
    );
  });

  await run('an unauthenticated client cannot upload a garment image', async () => {
    const anon = storageFor(null);
    await assertFails(
      uploadBytes(
        ref(anon, 'products/oxford/vto/garment-black-v9.png'),
        pngBytes,
        vtoWriteMeta('image/png'),
      ),
    );
  });

  await run('a superAdmin can delete a garment image; a customer cannot', async () => {
    await seed('products/oxford/vto/garment-gray-v1.png', pngBytes, 'image/png');
    const admin = storageFor(ADMIN, { role: 'superAdmin' });
    const alice = storageFor(ALICE, { role: 'customer' });
    await assertFails(deleteObject(ref(alice, 'products/oxford/vto/garment-gray-v1.png')));
    await assertSucceeds(deleteObject(ref(admin, 'products/oxford/vto/garment-gray-v1.png')));
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
