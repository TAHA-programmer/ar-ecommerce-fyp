// Firestore Security Rules verification for TWin AR Phase 8.4 (`users/{uid}`),
// Phase 8.5 (`products/{id}` reads), Phase 8.6 (`products/{id}` writes),
// Phase 8.8 (`categories/{categoryId}`), Phase 8.9
// (`orders/{orderId}` + `payments/{paymentId}`, interim pre-Stripe),
// Phase 8.10 (`users/{uid}/addresses`, `users/{uid}/addressDefault/pointer`,
// `users/{uid}/favorites`, `users/{uid}/cart`), Phase 8.11 (no customer
// product-stock write; Admin `stockQuantity` + `lastStockUpdatedAt` edit),
// Phase 8.12 (`users/{uid}` `displayName` shape validation + a strict
// Pakistani local-mobile `phone` format `^03[0-9]{9}$` - enforced on
// create and only on a real phone change on update, so a pre-8.12 profile
// is never locked out), Phase 8.13.1 (`checkoutSessions/{sessionId}` -
// owner/admin read, `write: if false` for every client including the Cloud
// Function's future writes going through the Admin SDK), and Phase 8.13.3
// (`stripeEvents/{eventId}` - the server-only Stripe webhook ledger, NO
// client read/write at all; unknown collections stay catch-all-denied).
// Runs against the real Firestore emulator - full fidelity for
// `request.resource.data` field-shape checks, which `fake_cloud_firestore`
// (used in `flutter test`) does not support. Invoked via `npm test` here,
// which wraps this script in `firebase emulators:exec`. Not part of the
// Flutter build/app runtime - a separate, one-off verification toolchain
// per 13_TESTING_AND_QA_RULES.md's Lean Testing Policy.

import { readFileSync } from 'fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc,
  setDoc,
  updateDoc,
  deleteDoc,
  getDoc,
  getDocs,
  collection,
  query,
  where,
  orderBy,
  limit,
  serverTimestamp,
  writeBatch,
  runTransaction,
  Timestamp,
} from 'firebase/firestore';

const ALICE = 'alice-uid';
const BOB = 'bob-uid';
const ALICE_EMAIL = 'alice@example.com';
const BOB_EMAIL = 'bob@example.com';

const validAliceDoc = () => ({
  uid: ALICE,
  email: ALICE_EMAIL,
  displayName: 'Alice',
  phone: '03001234567',
  role: 'customer',
  createdAt: serverTimestamp(),
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

async function seedAlice() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `users/${ALICE}`), {
      uid: ALICE,
      email: ALICE_EMAIL,
      displayName: 'Alice',
      phone: '03001234567',
      role: 'customer',
      createdAt: serverTimestamp(),
    });
  });
}

async function main() {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-twin-ar-rules-test',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });

  console.log('users/{uid} - create');

  await run('owner can create their own customer doc', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), validAliceDoc()),
    );
  });

  await run('client cannot create itself as superAdmin', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        role: 'superAdmin',
      }),
    );
  });

  await run('a user cannot create a document for another uid', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${BOB}`), {
        ...validAliceDoc(),
        uid: BOB,
      }),
    );
  });

  await run('the uid field must match the caller\'s own uid', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        uid: BOB,
      }),
    );
  });

  await run('the email field must match the authenticated token email', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        email: 'spoofed@example.com',
      }),
    );
  });

  await run('an unauthenticated client cannot create any profile', async () => {
    await testEnv.clearFirestore();
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      setDoc(doc(anon.firestore(), `users/${ALICE}`), validAliceDoc()),
    );
  });

  await run('create with an unexpected extra field is denied', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        avatarUrl: 'https://example.com/pic.jpg',
      }),
    );
  });

  console.log('users/{uid} - read');

  await run('owner can read their own profile', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(getDoc(doc(alice.firestore(), `users/${ALICE}`)));
  });

  await run('a different signed-in customer cannot read someone else\'s profile', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(getDoc(doc(bob.firestore(), `users/${ALICE}`)));
  });

  await run('a superAdmin custom claim can read any profile', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(getDoc(doc(admin.firestore(), `users/${ALICE}`)));
  });

  console.log('users/{uid} - update');

  await run('owner can update displayName/phone', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        displayName: 'Alice Updated',
        phone: '03009998888',
      }),
    );
  });

  await run('owner cannot change role via update', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        role: 'superAdmin',
      }),
    );
  });

  await run('owner cannot change uid via update', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), { uid: BOB }),
    );
  });

  await run('owner cannot change email via update', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        email: 'new@example.com',
      }),
    );
  });

  await run('owner cannot change createdAt via update', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        createdAt: serverTimestamp(),
      }),
    );
  });

  await run('update adding an unexpected new field is denied', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        avatarUrl: 'https://example.com/pic.jpg',
      }),
    );
  });

  await run('update changing an unexpected existing field is denied', async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        avatarUrl: 'https://example.com/pic.jpg',
      });
    });
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        avatarUrl: 'https://example.com/new-pic.jpg',
      }),
    );
  });

  console.log('users/{uid} - displayName shape + Pakistani-mobile phone (Phase 8.12)');

  const name101 = 'a'.repeat(101);
  const name100 = 'a'.repeat(100);
  const VALID_PK = '03001234567';
  const VALID_PK_2 = '03009998888';

  // A pre-8.12 profile whose stored phone predates the strict
  // Pakistani-mobile format - written with rules disabled to simulate real
  // legacy data.
  async function seedLegacyAlice(phone = '+1 234-567-8900') {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `users/${ALICE}`), {
        uid: ALICE,
        email: ALICE_EMAIL,
        displayName: 'Alice',
        phone,
        role: 'customer',
        createdAt: serverTimestamp(),
      });
    });
  }

  // --- displayName shape (unchanged from the approved 8.12 rule) ---

  await run('create with a non-string displayName is denied', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        displayName: 12345,
      }),
    );
  });

  await run('create with an empty displayName is denied', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        displayName: '',
      }),
    );
  });

  await run('create with a whitespace-only displayName is denied', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        displayName: '   ',
      }),
    );
  });

  await run('create with a leading/trailing-whitespace displayName is denied', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        displayName: '  Alice  ',
      }),
    );
  });

  await run('create with a 101-character displayName is denied', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        displayName: name101,
      }),
    );
  });

  await run('create with a 100-character displayName + a valid PK mobile succeeds', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        displayName: name100,
      }),
    );
  });

  await run('update to an oversized displayName is denied', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        displayName: name101,
      }),
    );
  });

  await run('update to a whitespace-only displayName is denied', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), { displayName: '   ' }),
    );
  });

  // --- phone: strict Pakistani local mobile ^03[0-9]{9}$ ---

  await run('create with a valid 03XXXXXXXXX phone succeeds', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      setDoc(doc(alice.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        phone: VALID_PK,
      }),
    );
  });

  for (const [label, badPhone] of [
    ['a non-string phone', 1234567890],
    ['an empty phone', ''],
    ['a whitespace-only phone', '   '],
    ['fewer than 11 digits', '0300123456'],
    ['more than 11 digits', '030012345678'],
    ['a wrong prefix (04...)', '04001234567'],
    ['a wrong prefix (13...)', '13001234567'],
    ['the +92 international format', '+923001234567'],
    ['the 92... international format', '923001234567'],
    ['spaces', '0300 123 4567'],
    ['hyphens', '0300-123-4567'],
    ['brackets', '(0300)1234567'],
    ['letters', '0300abcdefg'],
  ]) {
    await run(`create with ${label} is denied`, async () => {
      await testEnv.clearFirestore();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(
        setDoc(doc(alice.firestore(), `users/${ALICE}`), {
          ...validAliceDoc(),
          phone: badPhone,
        }),
      );
    });
  }

  await run('update changing phone to another valid 03XXXXXXXXX succeeds', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), { phone: VALID_PK_2 }),
    );
  });

  for (const [label, badPhone] of [
    ['fewer than 11 digits', '0300123456'],
    ['more than 11 digits', '030012345678'],
    ['a wrong prefix', '04001234567'],
    ['the +92 format', '+923001234567'],
    ['spaces', '0300 123 4567'],
    ['hyphens', '0300-123-4567'],
    ['letters', '0300abcdefg'],
    ['an empty value', ''],
  ]) {
    await run(`update changing phone to ${label} is denied`, async () => {
      await testEnv.clearFirestore();
      await seedAlice();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(
        updateDoc(doc(alice.firestore(), `users/${ALICE}`), { phone: badPhone }),
      );
    });
  }

  // --- legacy-safety: phone validated strictly on create and only when it
  //     actually changes on update, so a pre-8.12 profile is never locked
  //     out of legitimate operations ---

  await run('legacy profile: an avatar-only update succeeds (phone unchanged, not re-validated)', async () => {
    await testEnv.clearFirestore();
    await seedLegacyAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        avatarStoragePath: `users/${ALICE}/profile/pic.jpg`,
      }),
    );
  });

  await run('legacy profile: a name-only edit that re-writes the SAME stored phone succeeds', async () => {
    await testEnv.clearFirestore();
    await seedLegacyAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        displayName: 'Alice New Name',
        phone: '+1 234-567-8900', // unchanged legacy value
      }),
    );
  });

  await run('legacy profile: changing phone to another INVALID value is denied', async () => {
    await testEnv.clearFirestore();
    await seedLegacyAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        phone: '99999999999',
      }),
    );
  });

  await run('legacy profile: fixing the phone to a valid 03XXXXXXXXX succeeds', async () => {
    await testEnv.clearFirestore();
    await seedLegacyAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), { phone: VALID_PK }),
    );
  });

  // --- regressions ---

  await run('an avatar-only update still succeeds (displayName/phone not in the write payload)', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        avatarStoragePath: `users/${ALICE}/profile/pic.jpg`,
      }),
    );
  });

  await run('a non-owner still cannot update another user\'s profile (Phase 8.12 regression)', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(
      updateDoc(doc(bob.firestore(), `users/${ALICE}`), { displayName: 'Hacked' }),
    );
  });

  await run('role escalation via update is still denied even with an otherwise-valid displayName (Phase 8.12 regression)', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        displayName: 'Alice Still Valid',
        role: 'superAdmin',
      }),
    );
  });

  console.log('users/{uid} - update avatarStoragePath (Phase 8.7)');

  await run('owner can set avatarStoragePath to a path under their own uid', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        avatarStoragePath: `users/${ALICE}/profile/abc.jpg`,
      }),
    );
  });

  await run('owner can clear avatarStoragePath back to null', async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `users/${ALICE}`), {
        ...validAliceDoc(),
        avatarStoragePath: `users/${ALICE}/profile/abc.jpg`,
      });
    });
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        avatarStoragePath: null,
      }),
    );
  });

  await run('owner can update avatarStoragePath alongside displayName/phone in one write', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
        displayName: 'New Name',
        phone: '03009998888',
        avatarStoragePath: `users/${ALICE}/profile/abc.jpg`,
      }),
    );
  });

  await run(
    'owner CANNOT set avatarStoragePath to a path under a different uid - the core cross-user-avatar guard',
    async () => {
      await testEnv.clearFirestore();
      await seedAlice();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(
        updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
          avatarStoragePath: `users/${BOB}/profile/hijack.jpg`,
        }),
      );
    },
  );

  await run(
    'owner cannot set avatarStoragePath to an arbitrary string outside the users/{uid}/profile/ prefix',
    async () => {
      await testEnv.clearFirestore();
      await seedAlice();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(
        updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
          avatarStoragePath: 'https://evil.example.com/not-a-storage-path.jpg',
        }),
      );
    },
  );

  await run(
    'owner cannot set avatarStoragePath to a nested path under their own uid - exactly one filename segment is required',
    async () => {
      await testEnv.clearFirestore();
      await seedAlice();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(
        updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
          avatarStoragePath: `users/${ALICE}/profile/nested/hack.jpg`,
        }),
      );
    },
  );

  await run('a non-owner cannot set someone else\'s avatarStoragePath', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(
      updateDoc(doc(bob.firestore(), `users/${ALICE}`), {
        avatarStoragePath: `users/${ALICE}/profile/hijack.jpg`,
      }),
    );
  });

  await run(
    'setting avatarStoragePath cannot be used to smuggle a role change through in the same write',
    async () => {
      await testEnv.clearFirestore();
      await seedAlice();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(
        updateDoc(doc(alice.firestore(), `users/${ALICE}`), {
          avatarStoragePath: `users/${ALICE}/profile/abc.jpg`,
          role: 'superAdmin',
        }),
      );
    },
  );

  await run('a non-owner cannot update someone else\'s profile', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(
      updateDoc(doc(bob.firestore(), `users/${ALICE}`), {
        displayName: 'Hijacked',
      }),
    );
  });

  console.log('users/{uid} - delete');

  await run('delete is always denied, even for the owner', async () => {
    await testEnv.clearFirestore();
    await seedAlice();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(deleteDoc(doc(alice.firestore(), `users/${ALICE}`)));
  });

  console.log('products/{id} - read (Phase 8.5)');

  const publishedActiveProduct = () => ({
    title: 'Published Active Product',
    publicationStatus: 'published',
    isActive: true,
  });
  const draftProduct = () => ({
    title: 'Draft Product',
    publicationStatus: 'draft',
    isActive: true,
  });
  const inactiveProduct = () => ({
    title: 'Inactive Product',
    publicationStatus: 'published',
    isActive: false,
  });

  async function seedProduct(id, data) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `products/${id}`), data);
    });
  }

  await run('a signed-in customer can read a published + active product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', publishedActiveProduct());
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(getDoc(doc(alice.firestore(), 'products/p1')));
  });

  await run('a signed-in customer cannot read a draft product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', draftProduct());
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(getDoc(doc(alice.firestore(), 'products/p1')));
  });

  await run('a signed-in customer cannot read an inactive product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', inactiveProduct());
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(getDoc(doc(alice.firestore(), 'products/p1')));
  });

  await run('an unauthenticated client cannot read any product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', publishedActiveProduct());
    const anon = testEnv.unauthenticatedContext();
    await assertFails(getDoc(doc(anon.firestore(), 'products/p1')));
  });

  await run('a superAdmin custom claim can read a draft product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', draftProduct());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(getDoc(doc(admin.firestore(), 'products/p1')));
  });

  await run('a superAdmin custom claim can read an inactive product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', inactiveProduct());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(getDoc(doc(admin.firestore(), 'products/p1')));
  });

  console.log('products/{id} - write (Phase 8.6)');

  await run('a superAdmin custom claim can create a product', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(
      setDoc(doc(admin.firestore(), 'products/p1'), publishedActiveProduct()),
    );
  });

  await run('a superAdmin custom claim can update a product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', publishedActiveProduct());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(
      updateDoc(doc(admin.firestore(), 'products/p1'), { isActive: false }),
    );
  });

  await run('a superAdmin custom claim can delete a product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', publishedActiveProduct());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(deleteDoc(doc(admin.firestore(), 'products/p1')));
  });

  await run('a signed-in customer cannot create a product', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), 'products/p1'), publishedActiveProduct()),
    );
  });

  await run('a signed-in customer cannot update a product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', publishedActiveProduct());
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), 'products/p1'), { isActive: false }),
    );
  });

  await run('a signed-in customer cannot delete a product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', publishedActiveProduct());
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(deleteDoc(doc(alice.firestore(), 'products/p1')));
  });

  await run('an unauthenticated client cannot write a product', async () => {
    await testEnv.clearFirestore();
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      setDoc(doc(anon.firestore(), 'products/p1'), publishedActiveProduct()),
    );
  });

  console.log('products/{id} - stock / lastStockUpdatedAt writes (Phase 8.11 / 8.12)');

  await run('a signed-in customer cannot decrement a product\'s stockQuantity (Phase 8.11: no customer product-stock write exists)', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', { ...publishedActiveProduct(), stockQuantity: 5 });
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), 'products/p1'), { stockQuantity: 4 }),
    );
  });

  await run('a signed-in customer cannot write lastStockUpdatedAt on a product', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', { ...publishedActiveProduct(), stockQuantity: 5 });
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), 'products/p1'), {
        lastStockUpdatedAt: serverTimestamp(),
      }),
    );
  });

  await run('a superAdmin can update stockQuantity + lastStockUpdatedAt together (Phase 8.11 Admin inventory edit)', async () => {
    await testEnv.clearFirestore();
    await seedProduct('p1', { ...publishedActiveProduct(), stockQuantity: 5 });
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(
      updateDoc(doc(admin.firestore(), 'products/p1'), {
        stockQuantity: 3,
        lastStockUpdatedAt: serverTimestamp(),
      }),
    );
  });

  console.log('categories/{categoryId} - create (Phase 8.8)');

  const validCategory = (overrides = {}) => ({
    name: 'Furniture',
    key: 'furniture',
    kind: 'furniture',
    imageUrl: '',
    isActive: true,
    sortOrder: 10,
    ...overrides,
  });

  await run('a superAdmin can create a category with the full valid field set', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(
      setDoc(doc(admin.firestore(), 'categories/furniture'), validCategory()),
    );
  });

  await run('a superAdmin can create a category with a real Storage image URL', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({
          imageUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/categories%2Ffurniture%2Fimages%2Fimg.png?alt=media',
        }),
      ),
    );
  });

  await run('create is denied when key does not equal the document id', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ key: 'not-furniture' }),
      ),
    );
  });

  await run('create is denied for a kind outside the closed five-value set', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ kind: 'all' }),
      ),
    );
  });

  await run('create is denied for a completely invalid kind string', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ kind: 'not-a-real-kind' }),
      ),
    );
  });

  await run('create is denied when name is empty', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ name: '' }),
      ),
    );
  });

  await run('create is denied when name exceeds 60 characters', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ name: 'x'.repeat(61) }),
      ),
    );
  });

  await run('create is denied when name is whitespace-only', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ name: '   ' }),
      ),
    );
  });

  await run('create is denied when name has leading whitespace', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ name: ' Furniture' }),
      ),
    );
  });

  await run('create is denied when name has trailing whitespace', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ name: 'Furniture ' }),
      ),
    );
  });

  await run('create still succeeds for a valid internal-whitespace name (regression guard)', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(
      setDoc(
        doc(admin.firestore(), 'categories/outdoor-furniture'),
        validCategory({ name: 'Outdoor Furniture', key: 'outdoor-furniture' }),
      ),
    );
  });

  await run('create is denied when sortOrder is negative', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ sortOrder: -1 }),
      ),
    );
  });

  await run('create is denied when sortOrder is a fractional number', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ sortOrder: 10.5 }),
      ),
    );
  });

  for (const badKey of ['---', '-decor', 'decor-', 'home--decor']) {
    await run(`create is denied for a malformed key "${badKey}" (not the canonical slug shape)`, async () => {
      await testEnv.clearFirestore();
      const admin = testEnv.authenticatedContext('admin-uid', {
        email: 'admin@example.com',
        role: 'superAdmin',
      });
      await assertFails(
        setDoc(
          doc(admin.firestore(), `categories/${badKey}`),
          validCategory({ key: badKey, name: 'Decor' }),
        ),
      );
    });
  }

  await run('create is denied when isActive is not a boolean', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ isActive: 'yes' }),
      ),
    );
  });

  await run('create is denied when an unexpected extra field is present', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'categories/furniture'),
        validCategory({ categoryKind: 'furniture' }),
      ),
    );
  });

  await run('create is denied when a required field is missing', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    const { sortOrder, ...missingSortOrder } = validCategory();
    await assertFails(
      setDoc(doc(admin.firestore(), 'categories/furniture'), missingSortOrder),
    );
  });

  await run('a signed-in customer cannot create a category', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), 'categories/furniture'), validCategory()),
    );
  });

  await run('an unauthenticated client cannot create a category', async () => {
    await testEnv.clearFirestore();
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      setDoc(doc(anon.firestore(), 'categories/furniture'), validCategory()),
    );
  });

  console.log('categories/{categoryId} - read (Phase 8.8)');

  async function seedCategory(id, data) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `categories/${id}`), data);
    });
  }

  await run('a signed-in customer can read an active category', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory());
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(getDoc(doc(alice.firestore(), 'categories/furniture')));
  });

  await run('a signed-in customer cannot read an inactive category', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory({ isActive: false }));
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(getDoc(doc(alice.firestore(), 'categories/furniture')));
  });

  await run('an unauthenticated client cannot read any category', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory());
    const anon = testEnv.unauthenticatedContext();
    await assertFails(getDoc(doc(anon.firestore(), 'categories/furniture')));
  });

  await run('a superAdmin can read an active category', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(getDoc(doc(admin.firestore(), 'categories/furniture')));
  });

  await run('a superAdmin can read an inactive category', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory({ isActive: false }));
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(getDoc(doc(admin.firestore(), 'categories/furniture')));
  });

  console.log('categories/{categoryId} - update (Phase 8.8)');

  await run('a superAdmin can update name/imageUrl/isActive/sortOrder', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(
      updateDoc(doc(admin.firestore(), 'categories/furniture'), {
        name: 'Home Furniture',
        imageUrl: 'https://x.example/img.png',
        isActive: false,
        sortOrder: 40,
      }),
    );
  });

  await run('a superAdmin cannot change key on update', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      updateDoc(doc(admin.firestore(), 'categories/furniture'), {
        key: 'not-furniture',
      }),
    );
  });

  await run('a superAdmin cannot change kind on update - permanent, not just an oversight (see firestore.rules Phase 8.8 header comment)', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      updateDoc(doc(admin.firestore(), 'categories/furniture'), {
        kind: 'decor',
      }),
    );
  });

  await run('update is denied when the updated name exceeds 60 characters', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      updateDoc(doc(admin.firestore(), 'categories/furniture'), {
        name: 'x'.repeat(61),
      }),
    );
  });

  await run('update is denied when the updated name is whitespace-only', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      updateDoc(doc(admin.firestore(), 'categories/furniture'), {
        name: '   ',
      }),
    );
  });

  await run('update is denied when sortOrder is a fractional number', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory());
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      updateDoc(doc(admin.firestore(), 'categories/furniture'), {
        sortOrder: 15.25,
      }),
    );
  });

  await run('a signed-in customer cannot update a category', async () => {
    await testEnv.clearFirestore();
    await seedCategory('furniture', validCategory());
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), 'categories/furniture'), {
        isActive: false,
      }),
    );
  });

  console.log('categories/{categoryId} - delete (Phase 8.8)');

  await run('a superAdmin can delete a non-seeded (custom) category', async () => {
    await testEnv.clearFirestore();
    await seedCategory('outdoor-furniture', validCategory({
      name: 'Outdoor Furniture',
      key: 'outdoor-furniture',
    }));
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(
      deleteDoc(doc(admin.firestore(), 'categories/outdoor-furniture')),
    );
  });

  for (const seededId of ['furniture', 'clothing', 'rugs', 'decor', 'lighting']) {
    await run(
      `a superAdmin CANNOT delete the permanently protected seeded category "${seededId}"`,
      async () => {
        await testEnv.clearFirestore();
        await seedCategory(seededId, validCategory({ key: seededId, kind: seededId }));
        const admin = testEnv.authenticatedContext('admin-uid', {
          email: 'admin@example.com',
          role: 'superAdmin',
        });
        await assertFails(deleteDoc(doc(admin.firestore(), `categories/${seededId}`)));
      },
    );
  }

  await run('a signed-in customer cannot delete a category', async () => {
    await testEnv.clearFirestore();
    await seedCategory('outdoor-furniture', validCategory({
      name: 'Outdoor Furniture',
      key: 'outdoor-furniture',
    }));
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      deleteDoc(doc(alice.firestore(), 'categories/outdoor-furniture')),
    );
  });

  console.log('orders/{orderId} + payments/{paymentId} - Phase 8.9');

  // Mirrors the Dart-side toFirestoreCreateMap() shape exactly - see
  // order_firestore_mapper.dart / payment_firestore_mapper.dart.
  function validAddress(overrides = {}) {
    return {
      id: 'a1',
      label: 'Home',
      fullName: 'Test User',
      phoneNumber: '9999999999',
      addressLine1: '123 Test Street',
      addressLine2: null,
      city: 'Test City',
      provinceOrState: 'Test State',
      postalCode: '00000',
      isDefault: true,
      ...overrides,
    };
  }

  function validItems() {
    return [
      {
        productId: 'p1',
        productName: 'Test Product',
        imagePath: 'assets/test.png',
        imageSource: 'asset',
        quantity: 1,
        selectedSize: null,
        selectedColor: null,
        unitPrice: 1000,
        lineTotal: 1000,
      },
    ];
  }

  function validOrder({ userId, paymentId, total = 1000, overrides = {} }) {
    return {
      userId,
      paymentId,
      items: validItems(),
      orderDate: serverTimestamp(),
      subtotal: total,
      deliveryFee: 0,
      discount: 0,
      total,
      paymentMethod: 'stripeCard',
      paymentStatus: 'paid',
      orderStatus: 'pending',
      deliveryAddress: validAddress(),
      estimatedDeliveryStart: Timestamp.fromDate(
        new Date(Date.now() + 7 * 86400000),
      ),
      estimatedDeliveryEnd: Timestamp.fromDate(
        new Date(Date.now() + 14 * 86400000),
      ),
      ...overrides,
    };
  }

  function validPayment({ userId, orderId, amount = 1000, overrides = {} }) {
    return {
      userId,
      orderId,
      amount,
      method: 'stripeCard',
      status: 'paid',
      createdAt: serverTimestamp(),
      ...overrides,
    };
  }

  // Writes both documents in the SAME batch - required for getAfter()-based
  // mutual validation to see each other (see firestore.rules' header
  // comment on orderMatchesPayment/paymentMatchesOrder).
  async function createPair(ctx, { orderId, paymentId, userId, total = 1000, orderOverrides = {}, paymentOverrides = {} }) {
    const batch = writeBatch(ctx.firestore());
    batch.set(
      doc(ctx.firestore(), `orders/${orderId}`),
      validOrder({ userId, paymentId, total, overrides: orderOverrides }),
    );
    batch.set(
      doc(ctx.firestore(), `payments/${paymentId}`),
      validPayment({ userId, orderId, amount: total, overrides: paymentOverrides }),
    );
    return batch.commit();
  }

  async function seedPair(ownerUid, { orderId, paymentId, total = 1000 } = {}) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await createPair(context, { orderId, paymentId, userId: ownerUid, total });
    });
  }

  // Phase 8.13.6 - Final Security Cutover: `orders`/`payments` `create` is
  // now `if false` for EVERY client. Only the `stripeWebhook` /
  // `releaseExpiredReservations` Cloud Functions create them, via the Admin
  // SDK (which bypasses these rules). The Phase 8.9 client `create` rule and
  // its `isValidOrderCreate` / `orderMatchesPayment` field-shape /
  // `getAfter()` pairing checks - and the `resource == null` read allowance
  // that the client's pre-write `transaction.get()` needed - are all gone.
  console.log('orders/payments - Phase 8.13.6 cutover: no client create path');

  // The get()-before-write transaction shape the removed client used.
  async function createPairViaTransaction(ctx, { orderId, paymentId, userId, total = 1000 }) {
    const orderRef = doc(ctx.firestore(), `orders/${orderId}`);
    const paymentRef = doc(ctx.firestore(), `payments/${paymentId}`);
    return runTransaction(ctx.firestore(), async (transaction) => {
      const orderSnap = await transaction.get(orderRef);
      if (orderSnap.exists()) throw new Error('order id collision');
      const paymentSnap = await transaction.get(paymentRef);
      if (paymentSnap.exists()) throw new Error('payment id collision');
      transaction.set(orderRef, validOrder({ userId, paymentId, total }));
      transaction.set(paymentRef, validPayment({ userId, orderId, amount: total }));
    });
  }

  await run('a customer CANNOT create an order, even a perfectly well-formed one', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), 'orders/#TW1'),
        validOrder({ userId: ALICE, paymentId: 'pay1' }),
      ),
    );
  });

  await run('a customer CANNOT create a payment, even a perfectly well-formed one', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), 'payments/pay1'),
        validPayment({ userId: ALICE, orderId: '#TW1' }),
      ),
    );
  });

  await run('a customer CANNOT create a matching order+payment pair in one batch', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      createPair(alice, { orderId: '#TW1', paymentId: 'pay1', userId: ALICE }),
    );
  });

  await run('a customer CANNOT create an order via the get()-before-write transaction shape either', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      createPairViaTransaction(alice, {
        orderId: '#TW-txn',
        paymentId: 'pay-txn',
        userId: ALICE,
      }),
    );
  });

  await run('a superAdmin ALSO cannot create an order/payment (only the Cloud Functions / Admin SDK can)', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'orders/#TW-admin'),
        validOrder({ userId: 'admin-uid', paymentId: 'pay-admin' }),
      ),
    );
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'payments/pay-admin'),
        validPayment({ userId: 'admin-uid', orderId: '#TW-admin' }),
      ),
    );
  });

  await run('an unauthenticated client cannot create an order/payment', async () => {
    await testEnv.clearFirestore();
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      setDoc(
        doc(anon.firestore(), 'orders/#TW-anon'),
        validOrder({ userId: ALICE, paymentId: 'pay-anon' }),
      ),
    );
  });

  await run(
    'a customer reading their OWN not-yet-existing order/payment id is NOW denied (the Phase 8.9 resource==null read allowance is gone with the client create path)',
    async () => {
      await testEnv.clearFirestore();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(getDoc(doc(alice.firestore(), 'orders/#TW-nonexistent')));
      await assertFails(getDoc(doc(alice.firestore(), 'payments/pay-nonexistent')));
    },
  );

  await run(
    'an admin reading a nonexistent order/payment id still succeeds (isAdmin() short-circuits before resource.data)',
    async () => {
      await testEnv.clearFirestore();
      const admin = testEnv.authenticatedContext('admin-uid', {
        email: 'admin@example.com',
        role: 'superAdmin',
      });
      await assertSucceeds(getDoc(doc(admin.firestore(), 'orders/#TW-none')));
      await assertSucceeds(getDoc(doc(admin.firestore(), 'payments/pay-none')));
    },
  );

  await run(
    'a customer cannot overwrite an existing (server-created) order via a second write at the same id',
    async () => {
      await testEnv.clearFirestore();
      await seedPair(ALICE, { orderId: '#TW-dup', paymentId: 'pay-dup' });
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(
        setDoc(
          doc(alice.firestore(), 'orders/#TW-dup'),
          validOrder({ userId: ALICE, paymentId: 'pay-dup-new' }),
        ),
      );
    },
  );

  console.log('orders/payments - customer isolation, admin visibility');

  await run("a customer can read their own order and payment", async () => {
    await testEnv.clearFirestore();
    await seedPair(ALICE, { orderId: '#TW-alice', paymentId: 'pay-alice' });
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(getDoc(doc(alice.firestore(), 'orders/#TW-alice')));
    await assertSucceeds(getDoc(doc(alice.firestore(), 'payments/pay-alice')));
  });

  await run(
    "a direct Customer A -> Customer B context switch never leaks A's order/payment to B",
    async () => {
      await testEnv.clearFirestore();
      await seedPair(ALICE, { orderId: '#TW-alice2', paymentId: 'pay-alice2' });

      const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
      await assertFails(getDoc(doc(bob.firestore(), 'orders/#TW-alice2')));
      await assertFails(getDoc(doc(bob.firestore(), 'payments/pay-alice2')));

      // Bob's own pair is unaffected and fully readable by Bob.
      await seedPair(BOB, { orderId: '#TW-bob2', paymentId: 'pay-bob2' });
      await assertSucceeds(getDoc(doc(bob.firestore(), 'orders/#TW-bob2')));
      await assertSucceeds(getDoc(doc(bob.firestore(), 'payments/pay-bob2')));

      // And Alice still cannot see Bob's.
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(getDoc(doc(alice.firestore(), 'orders/#TW-bob2')));
    },
  );

  await run('a superAdmin can read any order and payment', async () => {
    await testEnv.clearFirestore();
    await seedPair(ALICE, { orderId: '#TW-alice3', paymentId: 'pay-alice3' });
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(getDoc(doc(admin.firestore(), 'orders/#TW-alice3')));
    await assertSucceeds(getDoc(doc(admin.firestore(), 'payments/pay-alice3')));
  });

  await run('an unauthenticated caller cannot read any order or payment', async () => {
    await testEnv.clearFirestore();
    await seedPair(ALICE, { orderId: '#TW-alice4', paymentId: 'pay-alice4' });
    const anon = testEnv.unauthenticatedContext();
    await assertFails(getDoc(doc(anon.firestore(), 'orders/#TW-alice4')));
    await assertFails(getDoc(doc(anon.firestore(), 'payments/pay-alice4')));
  });

  console.log('orders/{orderId} - locked status-transition graph (admin update)');

  const allowedTransitions = [
    ['pending', 'confirmed'],
    ['pending', 'cancelled'],
    ['confirmed', 'shipped'],
    ['confirmed', 'cancelled'],
    ['shipped', 'delivered'],
    ['shipped', 'cancelled'],
  ];
  const rejectedTransitions = [
    ['pending', 'shipped'], // skip
    ['pending', 'delivered'], // skip
    ['confirmed', 'pending'], // backward
    ['shipped', 'confirmed'], // backward
    ['delivered', 'pending'], // terminal
    ['delivered', 'cancelled'], // terminal
    ['cancelled', 'pending'], // terminal
  ];

  for (const [from, to] of allowedTransitions) {
    await run(`admin CAN transition an order ${from} -> ${to}`, async () => {
      await testEnv.clearFirestore();
      const orderId = `#TW-${from}-${to}`;
      await seedPair(ALICE, { orderId, paymentId: `pay-${from}-${to}` });
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(
          doc(context.firestore(), `orders/${orderId}`),
          { orderStatus: from },
          { merge: true },
        );
      });
      const admin = testEnv.authenticatedContext('admin-uid', {
        email: 'admin@example.com',
        role: 'superAdmin',
      });
      await assertSucceeds(
        updateDoc(doc(admin.firestore(), `orders/${orderId}`), { orderStatus: to }),
      );
    });
  }

  for (const [from, to] of rejectedTransitions) {
    await run(`admin CANNOT transition an order ${from} -> ${to}`, async () => {
      await testEnv.clearFirestore();
      const orderId = `#TW-${from}-${to}-bad`;
      await seedPair(ALICE, { orderId, paymentId: `pay-${from}-${to}-bad` });
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(
          doc(context.firestore(), `orders/${orderId}`),
          { orderStatus: from },
          { merge: true },
        );
      });
      const admin = testEnv.authenticatedContext('admin-uid', {
        email: 'admin@example.com',
        role: 'superAdmin',
      });
      await assertFails(
        updateDoc(doc(admin.firestore(), `orders/${orderId}`), { orderStatus: to }),
      );
    });
  }

  await run('a customer (non-admin) cannot update order status at all', async () => {
    await testEnv.clearFirestore();
    await seedPair(ALICE, { orderId: '#TW-cust-update', paymentId: 'pay-cust-update' });
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), 'orders/#TW-cust-update'), {
        orderStatus: 'confirmed',
      }),
    );
  });

  await run('an admin update touching any field other than orderStatus is rejected', async () => {
    await testEnv.clearFirestore();
    await seedPair(ALICE, { orderId: '#TW-other-field', paymentId: 'pay-other-field' });
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      updateDoc(doc(admin.firestore(), 'orders/#TW-other-field'), { total: 5000 }),
    );
    await assertFails(
      updateDoc(doc(admin.firestore(), 'orders/#TW-other-field'), {
        orderStatus: 'confirmed',
        total: 5000,
      }),
    );
  });

  await run('a payment can never be updated, even by an admin', async () => {
    await testEnv.clearFirestore();
    await seedPair(ALICE, { orderId: '#TW-pay-update', paymentId: 'pay-update' });
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      updateDoc(doc(admin.firestore(), 'payments/pay-update'), { status: 'failed' }),
    );
  });

  await run('an order can never be deleted, even by an admin', async () => {
    await testEnv.clearFirestore();
    await seedPair(ALICE, { orderId: '#TW-del', paymentId: 'pay-del' });
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(deleteDoc(doc(admin.firestore(), 'orders/#TW-del')));
  });

  await run('a payment can never be deleted, even by an admin', async () => {
    await testEnv.clearFirestore();
    await seedPair(ALICE, { orderId: '#TW-del2', paymentId: 'pay-del2' });
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(deleteDoc(doc(admin.firestore(), 'payments/pay-del2')));
  });

  // Phase 8.13.6 - the Phase 8.9 `orders`/`payments` client-create field-shape
  // tests (extra/missing/wrong-typed fields, item-count bounds, monetary
  // ceiling, discount/total invariants, delivery-window, address shape,
  // paymentStatus/orderStatus/method literals) are GONE: `create` is now
  // `if false`, so the shape rule they exercised no longer exists. The
  // authoritative document shape is built and checked server-side in
  // `functions/src/lib/orderFromSession.ts` and covered by the Functions
  // emulator suite.

  console.log('users/{uid}/addresses/{addressId} - Phase 8.10');

  function validAddressCreate(overrides = {}) {
    return {
      label: 'Home',
      fullName: 'Test User',
      phoneNumber: '9999999999',
      addressLine1: '123 Test Street',
      addressLine2: null,
      city: 'Test City',
      provinceOrState: 'Test State',
      postalCode: '00000',
      createdAt: serverTimestamp(),
      ...overrides,
    };
  }

  await run('an owner can create their own address with a full valid shape', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      setDoc(doc(alice.firestore(), `users/${ALICE}/addresses/a1`), validAddressCreate()),
    );
  });

  await run('a user cannot create an address under another uid', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${BOB}/addresses/a1`), validAddressCreate()),
    );
  });

  await run('an unauthenticated client cannot create an address', async () => {
    await testEnv.clearFirestore();
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      setDoc(doc(anon.firestore(), `users/${ALICE}/addresses/a1`), validAddressCreate()),
    );
  });

  await run('an address create missing a required key is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    const bad = validAddressCreate();
    delete bad.postalCode;
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}/addresses/a1`), bad),
    );
  });

  await run('an address create with an extra unknown field is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/addresses/a1`),
        validAddressCreate({ isDefault: true }),
      ),
    );
  });

  await run('an address create with an empty fullName is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/addresses/a1`),
        validAddressCreate({ fullName: '' }),
      ),
    );
  });

  await run('an address create with a non-string label is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/addresses/a1`),
        validAddressCreate({ label: 123 }),
      ),
    );
  });

  await run('an address create with createdAt != request.time is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/addresses/a1`),
        validAddressCreate({ createdAt: Timestamp.fromDate(new Date(2020, 0, 1)) }),
      ),
    );
  });

  await run('label may be null (no label chosen)', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/addresses/a1`),
        validAddressCreate({ label: null }),
      ),
    );
  });

  async function seedAddress(uid, id, overrides = {}) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), `users/${uid}/addresses/${id}`),
        validAddressCreate({ createdAt: Timestamp.fromDate(new Date(2026, 0, 1)), ...overrides }),
      );
    });
  }

  await run('the owner can read their own address', async () => {
    await testEnv.clearFirestore();
    await seedAddress(ALICE, 'a1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(getDoc(doc(alice.firestore(), `users/${ALICE}/addresses/a1`)));
  });

  await run('another user cannot read someone else\'s address', async () => {
    await testEnv.clearFirestore();
    await seedAddress(ALICE, 'a1');
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(getDoc(doc(bob.firestore(), `users/${ALICE}/addresses/a1`)));
  });

  await run('the owner can update editable fields on their own address', async () => {
    await testEnv.clearFirestore();
    await seedAddress(ALICE, 'a1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}/addresses/a1`), {
        fullName: 'Updated Name',
      }),
    );
  });

  await run('createdAt is immutable - an update attempting to change it is rejected', async () => {
    await testEnv.clearFirestore();
    await seedAddress(ALICE, 'a1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}/addresses/a1`), {
        createdAt: serverTimestamp(),
      }),
    );
  });

  await run('another user cannot update someone else\'s address', async () => {
    await testEnv.clearFirestore();
    await seedAddress(ALICE, 'a1');
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(
      updateDoc(doc(bob.firestore(), `users/${ALICE}/addresses/a1`), {
        fullName: 'Hijacked',
      }),
    );
  });

  await run('the owner can delete their own address', async () => {
    await testEnv.clearFirestore();
    await seedAddress(ALICE, 'a1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(deleteDoc(doc(alice.firestore(), `users/${ALICE}/addresses/a1`)));
  });

  await run('another user cannot delete someone else\'s address', async () => {
    await testEnv.clearFirestore();
    await seedAddress(ALICE, 'a1');
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(deleteDoc(doc(bob.firestore(), `users/${ALICE}/addresses/a1`)));
  });

  console.log('users/{uid}/addressDefault/pointer - Phase 8.10');

  await run('the owner can set their own default-address pointer', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      setDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`), {
        defaultAddressId: 'a1',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await run('defaultAddressId may be null (no addresses left)', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      setDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`), {
        defaultAddressId: null,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await run('a user cannot write another user\'s default-address pointer', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${BOB}/addressDefault/pointer`), {
        defaultAddressId: 'a1',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await run('a default-address pointer write with an extra unknown field is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`), {
        defaultAddressId: 'a1',
        updatedAt: serverTimestamp(),
        extra: 'nope',
      }),
    );
  });

  await run('a default-address pointer write with updatedAt != request.time is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`), {
        defaultAddressId: 'a1',
        updatedAt: Timestamp.fromDate(new Date(2020, 0, 1)),
      }),
    );
  });

  await run('another user cannot read someone else\'s default-address pointer', async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `users/${ALICE}/addressDefault/pointer`), {
        defaultAddressId: 'a1',
        updatedAt: serverTimestamp(),
      });
    });
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(getDoc(doc(bob.firestore(), `users/${ALICE}/addressDefault/pointer`)));
  });

  await run('the default-address pointer can never be deleted (allow delete: if false)', async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `users/${ALICE}/addressDefault/pointer`), {
        defaultAddressId: 'a1',
        updatedAt: serverTimestamp(),
      });
    });
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(deleteDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`)));
  });

  await run(
    'a document ID other than the literal "pointer" under addressDefault '
      + 'is rejected - pre-deployment hardening (the original rule used an '
      + 'unconstrained {pointerId} wildcard)',
    async () => {
      await testEnv.clearFirestore();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(
        setDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/rogue`), {
          defaultAddressId: 'a1',
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  console.log(
    'users/{uid}/addresses + addressDefault/pointer - default-address '
      + 'concurrency (real emulator, pre-deployment correction pass)',
  );

  // These mirror `FirestoreAddressRepository`'s actual Dart algorithm
  // closely enough to prove the real Firestore transaction-conflict-retry
  // guarantees that design depends on - see that class's doc comment for
  // the exact races being reproduced here. Not reproducible with the same
  // fidelity against `fake_cloud_firestore` (see
  // `firestore_address_repository_test.dart`'s comment on this).

  // `createdAt` is always `serverTimestamp()` - the real create rule
  // requires `data.createdAt == request.time`, exactly mirroring
  // `AddressDraftFirestoreMapper.toFirestoreCreateMap()`, so a test cannot
  // pass an explicit past `Timestamp` here the way `seedAddress` (which
  // bypasses rules entirely) can. Tests that need a deterministic ordering
  // rely on awaiting each `jsAddAddress` call in the desired sequence
  // instead - real serverTimestamps are strictly increasing across
  // sequential awaited commits.
  async function jsAddAddress(ctx, uid, id, { makeDefault = false } = {}) {
    const addressRef = doc(ctx.firestore(), `users/${uid}/addresses/${id}`);
    const pointerRef = doc(ctx.firestore(), `users/${uid}/addressDefault/pointer`);
    await runTransaction(ctx.firestore(), async (transaction) => {
      const pointerSnap = await transaction.get(pointerRef);
      const currentDefaultId = pointerSnap.exists() ? pointerSnap.data().defaultAddressId : null;
      const becameDefault = makeDefault || typeof currentDefaultId !== 'string';
      transaction.set(addressRef, validAddressCreate({ createdAt: serverTimestamp() }));
      if (becameDefault) {
        transaction.set(pointerRef, { defaultAddressId: id, updatedAt: serverTimestamp() });
      }
    });
  }

  // One attempt only, given a PRE-DETERMINED candidateId (as if found by an
  // earlier, possibly now-stale outer query) - lets a test control exactly
  // when the "outer candidate query" logically happened relative to other
  // concurrent operations, which a single self-contained retry-loop
  // function couldn't express.
  async function jsDeleteAddressSingleAttempt(ctx, uid, addressId, candidateId) {
    const addressRef = doc(ctx.firestore(), `users/${uid}/addresses/${addressId}`);
    const pointerRef = doc(ctx.firestore(), `users/${uid}/addressDefault/pointer`);
    await runTransaction(ctx.firestore(), async (transaction) => {
      const addressSnap = await transaction.get(addressRef);
      if (!addressSnap.exists()) return;
      const pointerSnap = await transaction.get(pointerRef);
      const currentDefaultId = pointerSnap.exists() ? pointerSnap.data().defaultAddressId : null;
      const wasDefault = currentDefaultId === addressId;
      if (wasDefault && candidateId) {
        const candidateSnap = await transaction.get(
          doc(ctx.firestore(), `users/${uid}/addresses/${candidateId}`),
        );
        if (!candidateSnap.exists()) {
          throw new Error('CANDIDATE_GONE');
        }
      }
      transaction.delete(addressRef);
      if (wasDefault) {
        transaction.set(pointerRef, {
          defaultAddressId: candidateId || null,
          updatedAt: serverTimestamp(),
        });
      }
    });
  }

  async function jsReconcileMissingDefault(ctx, uid) {
    const q = query(
      collection(ctx.firestore(), `users/${uid}/addresses`),
      orderBy('createdAt'),
      limit(1),
    );
    const snap = await getDocs(q);
    if (snap.empty) return;
    const candidateId = snap.docs[0].id;
    const pointerRef = doc(ctx.firestore(), `users/${uid}/addressDefault/pointer`);
    await runTransaction(ctx.firestore(), async (transaction) => {
      const pointerSnap = await transaction.get(pointerRef);
      const currentDefaultId = pointerSnap.exists() ? pointerSnap.data().defaultAddressId : null;
      if (typeof currentDefaultId === 'string') return;
      const candidateSnap = await transaction.get(
        doc(ctx.firestore(), `users/${uid}/addresses/${candidateId}`),
      );
      if (!candidateSnap.exists()) return;
      transaction.set(pointerRef, { defaultAddressId: candidateId, updatedAt: serverTimestamp() });
    });
  }

  // Full retry-loop version (mirrors the real Dart method exactly) - used
  // by tests that don't need to control the interleaving explicitly.
  async function jsDeleteAddress(ctx, uid, addressId, maxAttempts = 3) {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      const q = query(
        collection(ctx.firestore(), `users/${uid}/addresses`),
        orderBy('createdAt'),
        limit(2),
      );
      const snap = await getDocs(q);
      const candidateId = snap.docs.map((d) => d.id).find((id) => id !== addressId) || '';
      try {
        await jsDeleteAddressSingleAttempt(ctx, uid, addressId, candidateId);
        await jsReconcileMissingDefault(ctx, uid);
        return;
      } catch (err) {
        if (err.message === 'CANDIDATE_GONE' && attempt < maxAttempts) continue;
        throw err;
      }
    }
  }

  await run(
    'a candidate that vanishes between the outer query and the transaction '
      + 'throws CANDIDATE_GONE (forcing the real repository\'s retry loop to '
      + 're-query), never silently committing a null default while the '
      + 'deleted address is left untouched',
    async () => {
      await testEnv.clearFirestore();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await seedAddress(ALICE, 'a1', { createdAt: Timestamp.fromDate(new Date(2026, 0, 1)) });
      await seedAddress(ALICE, 'a2', { createdAt: Timestamp.fromDate(new Date(2026, 0, 2)) });
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), `users/${ALICE}/addressDefault/pointer`), {
          defaultAddressId: 'a1',
          updatedAt: serverTimestamp(),
        });
      });
      // Simulate a2 (the previously-found candidate) being deleted by a
      // concurrent device AFTER it was found but BEFORE this attempt's
      // transaction reads it.
      await deleteDoc(doc(alice.firestore(), `users/${ALICE}/addresses/a2`));

      let threw = false;
      try {
        await jsDeleteAddressSingleAttempt(alice, ALICE, 'a1', 'a2');
      } catch (err) {
        threw = err.message === 'CANDIDATE_GONE';
      }
      if (!threw) throw new Error('expected CANDIDATE_GONE to be thrown');

      const a1Snap = await getDoc(doc(alice.firestore(), `users/${ALICE}/addresses/a1`));
      if (!a1Snap.exists()) {
        throw new Error('a1 should not have been deleted by the aborted attempt');
      }
    },
  );

  await run(
    'deleting the only (default) address while a concurrent device adds a '
      + 'new address converges to exactly one valid default - proves the '
      + 'real-Firestore transaction semantics the reconciliation safety net '
      + 'depends on (mirrors FirestoreAddressRepository.deleteAddress\'s '
      + 'doc comment exactly)',
    async () => {
      await testEnv.clearFirestore();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await jsAddAddress(alice, ALICE, 'a1');

      // Device A's outer candidate query happens NOW - finds none, since a1
      // is the only address at this moment.
      const staleCandidateFoundByDeviceA = '';

      // Device B's full addAddress commits BEFORE Device A's transaction:
      // the old default (a1) still exists at this point, so b1 is
      // correctly created as non-default.
      await jsAddAddress(alice, ALICE, 'b1');

      // Device A's transaction now runs, using its stale (empty) candidate -
      // deletes a1 and sets the pointer to null.
      await jsDeleteAddressSingleAttempt(alice, ALICE, 'a1', staleCandidateFoundByDeviceA);

      const midStateSnap = await getDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`));
      if (midStateSnap.data().defaultAddressId !== null) {
        throw new Error('expected the pointer to be null immediately after the stale-candidate delete');
      }

      // The real deleteAddress calls this unconditionally after every
      // successful transaction - this is what closes the gap.
      await jsReconcileMissingDefault(alice, ALICE);

      const finalSnap = await getDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`));
      if (finalSnap.data().defaultAddressId !== 'b1') {
        throw new Error(`expected b1 to be the healed default, got ${JSON.stringify(finalSnap.data())}`);
      }
    },
  );

  await run(
    'two devices concurrently claiming default for two different addresses '
      + 'converge to exactly one final default, never two',
    async () => {
      await testEnv.clearFirestore();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await seedAddress(ALICE, 'a1');
      await seedAddress(ALICE, 'a2');

      async function claimDefault(id) {
        const addressRef = doc(alice.firestore(), `users/${ALICE}/addresses/${id}`);
        const pointerRef = doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`);
        await runTransaction(alice.firestore(), async (transaction) => {
          const addressSnap = await transaction.get(addressRef);
          if (!addressSnap.exists()) throw new Error('address not found');
          transaction.set(pointerRef, { defaultAddressId: id, updatedAt: serverTimestamp() });
        });
      }

      await Promise.all([claimDefault('a1'), claimDefault('a2')]);

      const snap = await getDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`));
      const value = snap.data().defaultAddressId;
      if (value !== 'a1' && value !== 'a2') {
        throw new Error(`expected exactly one of a1/a2 to be default, got ${value}`);
      }
    },
  );

  await run('deleting the only address converges to a null default pointer, and the address is really gone', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await jsAddAddress(alice, ALICE, 'a1');

    await jsDeleteAddress(alice, ALICE, 'a1');

    const addressSnap = await getDoc(doc(alice.firestore(), `users/${ALICE}/addresses/a1`));
    if (addressSnap.exists()) throw new Error('a1 should be deleted');
    const pointerSnap = await getDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`));
    if (pointerSnap.data().defaultAddressId !== null) {
      throw new Error(`expected a null default, got ${JSON.stringify(pointerSnap.data())}`);
    }
  });

  await run(
    'invariant: after a sequence of add/delete operations completes, '
      + 'non-empty addresses always implies exactly one valid default '
      + 'pointer',
    async () => {
      await testEnv.clearFirestore();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await jsAddAddress(alice, ALICE, 'a1');
      await jsAddAddress(alice, ALICE, 'a2');
      await jsAddAddress(alice, ALICE, 'a3');
      await jsDeleteAddress(alice, ALICE, 'a1'); // was default - reassigns
      await jsDeleteAddress(alice, ALICE, 'a2'); // was default - reassigns again

      const remaining = await getDocs(collection(alice.firestore(), `users/${ALICE}/addresses`));
      if (remaining.empty) throw new Error('expected a3 to still exist');

      const pointerSnap = await getDoc(doc(alice.firestore(), `users/${ALICE}/addressDefault/pointer`));
      const defaultId = pointerSnap.data()?.defaultAddressId;
      const validIds = remaining.docs.map((d) => d.id);
      if (!validIds.includes(defaultId)) {
        throw new Error(
          `invariant violated: addresses ${JSON.stringify(validIds)} are non-empty but the default `
            + `pointer is ${JSON.stringify(defaultId)}`,
        );
      }
    },
  );

  console.log('users/{uid}/favorites/{productId} - Phase 8.10');

  await run('an owner can favorite a product (create)', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      setDoc(doc(alice.firestore(), `users/${ALICE}/favorites/p1`), {
        addedAt: serverTimestamp(),
      }),
    );
  });

  await run('a user cannot create a favorite under another uid', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${BOB}/favorites/p1`), {
        addedAt: serverTimestamp(),
      }),
    );
  });

  await run('an unauthenticated client cannot create a favorite', async () => {
    await testEnv.clearFirestore();
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      setDoc(doc(anon.firestore(), `users/${ALICE}/favorites/p1`), {
        addedAt: serverTimestamp(),
      }),
    );
  });

  await run('a favorite create with an extra unknown field is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}/favorites/p1`), {
        addedAt: serverTimestamp(),
        note: 'nope',
      }),
    );
  });

  await run('a favorite create with addedAt != request.time is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${ALICE}/favorites/p1`), {
        addedAt: Timestamp.fromDate(new Date(2020, 0, 1)),
      }),
    );
  });

  async function seedFavorite(uid, productId) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `users/${uid}/favorites/${productId}`), {
        addedAt: serverTimestamp(),
      });
    });
  }

  await run('the owner can read their own favorite', async () => {
    await testEnv.clearFirestore();
    await seedFavorite(ALICE, 'p1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(getDoc(doc(alice.firestore(), `users/${ALICE}/favorites/p1`)));
  });

  await run('another user cannot read someone else\'s favorite', async () => {
    await testEnv.clearFirestore();
    await seedFavorite(ALICE, 'p1');
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(getDoc(doc(bob.firestore(), `users/${ALICE}/favorites/p1`)));
  });

  await run('a favorite can never be updated in place', async () => {
    await testEnv.clearFirestore();
    await seedFavorite(ALICE, 'p1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}/favorites/p1`), {
        addedAt: serverTimestamp(),
      }),
    );
  });

  await run('the owner can delete (unfavorite) their own favorite', async () => {
    await testEnv.clearFirestore();
    await seedFavorite(ALICE, 'p1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(deleteDoc(doc(alice.firestore(), `users/${ALICE}/favorites/p1`)));
  });

  await run('another user cannot delete someone else\'s favorite', async () => {
    await testEnv.clearFirestore();
    await seedFavorite(ALICE, 'p1');
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(deleteDoc(doc(bob.firestore(), `users/${ALICE}/favorites/p1`)));
  });

  console.log(
    'users/{uid}/favorites - addFavorite idempotency (real emulator, '
      + 'pre-deployment correction pass)',
  );

  // Mirrors `FirestoreFavoritesRepository.addFavorite`'s real
  // create-if-absent transaction - see that method's doc comment for the
  // exact bug this closes (a plain `.set()` on an already-existing document
  // is classified as `update` by Security Rules, which `favorites/{id}`
  // locks to `allow update: if false`).
  async function transactionalAddFavorite(ctx, uid, productId) {
    const docRef = doc(ctx.firestore(), `users/${uid}/favorites/${productId}`);
    await runTransaction(ctx.firestore(), async (transaction) => {
      const snap = await transaction.get(docRef);
      if (snap.exists()) return;
      transaction.set(docRef, { addedAt: serverTimestamp() });
    });
  }

  await run(
    'a plain (non-transactional) .set() re-favoriting an already-favorited '
      + 'product IS rejected by the locked update rule - this is the exact '
      + 'bug found by independent review, reproduced here against the REAL '
      + 'rules to document why addFavorite must use a transaction, not a '
      + 'bare .set()',
    async () => {
      await testEnv.clearFirestore();
      await seedFavorite(ALICE, 'p1');
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      await assertFails(
        setDoc(doc(alice.firestore(), `users/${ALICE}/favorites/p1`), {
          addedAt: serverTimestamp(),
        }),
      );
    },
  );

  await run(
    'the real create-if-absent transaction completes cleanly and '
      + 'idempotently when the favorite already exists - never hits the '
      + 'locked update rule',
    async () => {
      await testEnv.clearFirestore();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      const docRef = doc(alice.firestore(), `users/${ALICE}/favorites/p1`);

      await transactionalAddFavorite(alice, ALICE, 'p1');
      await transactionalAddFavorite(alice, ALICE, 'p1'); // repeat - must not throw

      const snap = await getDoc(docRef);
      if (!snap.exists()) throw new Error('favorite should exist');
    },
  );

  await run(
    'two concurrent transactional favorites of the same product converge '
      + 'to exactly one document, neither hitting the locked update rule',
    async () => {
      await testEnv.clearFirestore();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      const docRef = doc(alice.firestore(), `users/${ALICE}/favorites/p1`);

      await Promise.all([
        transactionalAddFavorite(alice, ALICE, 'p1'),
        transactionalAddFavorite(alice, ALICE, 'p1'),
      ]);

      const snap = await getDoc(docRef);
      if (!snap.exists()) throw new Error('favorite should exist');
    },
  );

  console.log('users/{uid}/cart/{cartItemId} - Phase 8.10');

  function validCartItemCreate(overrides = {}) {
    return {
      productId: 'p1',
      quantity: 2,
      selectedColor: 'blue',
      selectedSize: 'm',
      priceAmountSnapshot: 5000,
      addedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...overrides,
    };
  }

  await run('an owner can create a cart item with a full valid shape', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      setDoc(doc(alice.firestore(), `users/${ALICE}/cart/item1`), validCartItemCreate()),
    );
  });

  await run('null selectedColor/selectedSize are valid (no variant chosen)', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/cart/item1`),
        validCartItemCreate({ selectedColor: null, selectedSize: null }),
      ),
    );
  });

  await run('a user cannot create a cart item under another uid', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), `users/${BOB}/cart/item1`), validCartItemCreate()),
    );
  });

  await run('an unauthenticated client cannot create a cart item', async () => {
    await testEnv.clearFirestore();
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      setDoc(doc(anon.firestore(), `users/${ALICE}/cart/item1`), validCartItemCreate()),
    );
  });

  await run('a cart item create with quantity 0 is rejected (below minimum)', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/cart/item1`),
        validCartItemCreate({ quantity: 0 }),
      ),
    );
  });

  await run('a cart item create with quantity 100 is rejected (above maximum)', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/cart/item1`),
        validCartItemCreate({ quantity: 100 }),
      ),
    );
  });

  await run('a cart item create with a non-integer quantity is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/cart/item1`),
        validCartItemCreate({ quantity: 2.5 }),
      ),
    );
  });

  await run('a cart item create with a negative priceAmountSnapshot is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/cart/item1`),
        validCartItemCreate({ priceAmountSnapshot: -1 }),
      ),
    );
  });

  await run('a cart item create with an empty productId is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/cart/item1`),
        validCartItemCreate({ productId: '' }),
      ),
    );
  });

  await run('a cart item create with an extra unknown field is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/cart/item1`),
        validCartItemCreate({ extra: 'nope' }),
      ),
    );
  });

  await run('a cart item create with addedAt != request.time is rejected', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), `users/${ALICE}/cart/item1`),
        validCartItemCreate({ addedAt: Timestamp.fromDate(new Date(2020, 0, 1)) }),
      ),
    );
  });

  async function seedCartItem(uid, id, overrides = {}) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), `users/${uid}/cart/${id}`),
        validCartItemCreate({
          addedAt: Timestamp.fromDate(new Date(2026, 0, 1)),
          updatedAt: Timestamp.fromDate(new Date(2026, 0, 1)),
          ...overrides,
        }),
      );
    });
  }

  await run('the owner can read their own cart item', async () => {
    await testEnv.clearFirestore();
    await seedCartItem(ALICE, 'item1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(getDoc(doc(alice.firestore(), `users/${ALICE}/cart/item1`)));
  });

  await run('another user cannot read someone else\'s cart item', async () => {
    await testEnv.clearFirestore();
    await seedCartItem(ALICE, 'item1');
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(getDoc(doc(bob.firestore(), `users/${ALICE}/cart/item1`)));
  });

  await run('the owner can update quantity (an absolute quantity change)', async () => {
    await testEnv.clearFirestore();
    await seedCartItem(ALICE, 'item1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      updateDoc(doc(alice.firestore(), `users/${ALICE}/cart/item1`), {
        quantity: 5,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await run('an update with quantity above the maximum is rejected', async () => {
    await testEnv.clearFirestore();
    await seedCartItem(ALICE, 'item1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}/cart/item1`), {
        quantity: 100,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await run('productId is immutable - an update attempting to change it is rejected', async () => {
    await testEnv.clearFirestore();
    await seedCartItem(ALICE, 'item1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}/cart/item1`), {
        productId: 'different-product',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await run('addedAt is immutable - an update attempting to change it is rejected', async () => {
    await testEnv.clearFirestore();
    await seedCartItem(ALICE, 'item1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}/cart/item1`), {
        addedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await run('selectedColor/selectedSize are immutable on update - a real '
      + 'variant change must be a new document (new deterministic key), '
      + 'never an in-place mutation', async () => {
    await testEnv.clearFirestore();
    await seedCartItem(ALICE, 'item1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `users/${ALICE}/cart/item1`), {
        selectedColor: 'red',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await run('another user cannot update someone else\'s cart item', async () => {
    await testEnv.clearFirestore();
    await seedCartItem(ALICE, 'item1');
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(
      updateDoc(doc(bob.firestore(), `users/${ALICE}/cart/item1`), {
        quantity: 5,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await run('the owner can delete (remove) their own cart item', async () => {
    await testEnv.clearFirestore();
    await seedCartItem(ALICE, 'item1');
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(deleteDoc(doc(alice.firestore(), `users/${ALICE}/cart/item1`)));
  });

  await run('another user cannot delete someone else\'s cart item', async () => {
    await testEnv.clearFirestore();
    await seedCartItem(ALICE, 'item1');
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(deleteDoc(doc(bob.firestore(), `users/${ALICE}/cart/item1`)));
  });

  console.log('users/{uid}/cart - concurrent atomic quantity merge (real emulator)');

  await run(
    'two concurrent addItem-style transactions for the SAME product/variant '
      + 'converge on the correctly SUMMED quantity - proves the real '
      + 'Firestore optimistic-concurrency retry this app\'s '
      + 'FirestoreCartRepository.addItem depends on (not reproducible '
      + 'against fake_cloud_firestore - see cart_viewmodel/'
      + 'firestore_cart_repository_test.dart\'s comment on this)',
    async () => {
      await testEnv.clearFirestore();
      const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
      const itemRef = doc(alice.firestore(), `users/${ALICE}/cart/merge-item`);

      async function addQuantity(qty) {
        return runTransaction(alice.firestore(), async (transaction) => {
          const snap = await transaction.get(itemRef);
          if (snap.exists()) {
            const existing = snap.data().quantity;
            transaction.update(itemRef, {
              quantity: Math.min(existing + qty, 99),
              updatedAt: serverTimestamp(),
            });
          } else {
            transaction.set(itemRef, validCartItemCreate({ quantity: qty }));
          }
        });
      }

      await Promise.all([addQuantity(2), addQuantity(3)]);

      const finalSnap = await getDoc(itemRef);
      if (finalSnap.data().quantity !== 5) {
        throw new Error(
          `expected merged quantity 5, got ${finalSnap.data().quantity}`,
        );
      }
    },
  );

  console.log('checkoutSessions/{sessionId} - Phase 8.13.1 (owner/admin read, server-written)');

  const CHECKOUT_SESSION_ID = 'cs_test_alice_1';

  function validCheckoutSession(overrides = {}) {
    return {
      userId: ALICE,
      items: [
        { productId: 'p1', quantity: 2, selectedColor: null, selectedSize: null },
      ],
      subtotal: 5000,
      deliveryFee: 500,
      discount: 1000,
      total: 4500,
      deliveryAddressSnapshot: { fullName: 'Alice', city: 'Karachi' },
      stripePaymentIntentId: null,
      status: 'reserved',
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 15 * 60 * 1000)),
      createdAt: serverTimestamp(),
      orderId: null,
      ...overrides,
    };
  }

  async function seedCheckoutSession(overrides = {}) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), `checkoutSessions/${CHECKOUT_SESSION_ID}`),
        validCheckoutSession(overrides),
      );
    });
  }

  await run('checkoutSessions: the owning customer can read their own session', async () => {
    await testEnv.clearFirestore();
    await seedCheckoutSession();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertSucceeds(
      getDoc(doc(alice.firestore(), `checkoutSessions/${CHECKOUT_SESSION_ID}`)),
    );
  });

  await run('checkoutSessions: a different signed-in user cannot read someone else\'s session', async () => {
    await testEnv.clearFirestore();
    await seedCheckoutSession();
    const bob = testEnv.authenticatedContext(BOB, { email: BOB_EMAIL });
    await assertFails(
      getDoc(doc(bob.firestore(), `checkoutSessions/${CHECKOUT_SESSION_ID}`)),
    );
  });

  await run('checkoutSessions: an unauthenticated client cannot read a session', async () => {
    await testEnv.clearFirestore();
    await seedCheckoutSession();
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      getDoc(doc(anon.firestore(), `checkoutSessions/${CHECKOUT_SESSION_ID}`)),
    );
  });

  await run('checkoutSessions: an admin can read any user\'s session (support/debug, mirrors orders/payments)', async () => {
    await testEnv.clearFirestore();
    await seedCheckoutSession();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(
      getDoc(doc(admin.firestore(), `checkoutSessions/${CHECKOUT_SESSION_ID}`)),
    );
  });

  await run('checkoutSessions: the owner CAN run the Phase 8.13.6 reconciler list query (where userId == own uid)', async () => {
    await testEnv.clearFirestore();
    await seedCheckoutSession();
    // Another user's session in the same collection - the scoped query must
    // still succeed and must not return it.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), 'checkoutSessions/cs_test_bob_1'),
        validCheckoutSession({ userId: BOB }),
      );
    });
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    const snap = await getDocs(
      query(
        collection(alice.firestore(), 'checkoutSessions'),
        where('userId', '==', ALICE),
        limit(40),
      ),
    );
    if (snap.size !== 1) throw new Error(`expected 1 own session, got ${snap.size}`);
  });

  await run('checkoutSessions: an unfiltered list query is denied for a non-admin (must be scoped to own uid)', async () => {
    await testEnv.clearFirestore();
    await seedCheckoutSession();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      getDocs(query(collection(alice.firestore(), 'checkoutSessions'), limit(40))),
    );
  });

  await run('checkoutSessions: the owner CANNOT create a session (server / Admin SDK only)', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(
        doc(alice.firestore(), 'checkoutSessions/cs_client_made'),
        validCheckoutSession(),
      ),
    );
  });

  await run('checkoutSessions: the owner CANNOT update their own session (e.g. flip status to succeeded)', async () => {
    await testEnv.clearFirestore();
    await seedCheckoutSession();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      updateDoc(doc(alice.firestore(), `checkoutSessions/${CHECKOUT_SESSION_ID}`), {
        status: 'succeeded',
      }),
    );
  });

  await run('checkoutSessions: a superAdmin CANNOT write a session either (write is `if false` for everyone)', async () => {
    await testEnv.clearFirestore();
    await seedCheckoutSession();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(
      setDoc(
        doc(admin.firestore(), 'checkoutSessions/cs_admin_made'),
        validCheckoutSession(),
      ),
    );
    await assertFails(
      updateDoc(doc(admin.firestore(), `checkoutSessions/${CHECKOUT_SESSION_ID}`), {
        status: 'failed',
      }),
    );
    await assertFails(
      deleteDoc(doc(admin.firestore(), `checkoutSessions/${CHECKOUT_SESSION_ID}`)),
    );
  });

  await run('checkoutSessions: the owner CANNOT delete their own session', async () => {
    await testEnv.clearFirestore();
    await seedCheckoutSession();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      deleteDoc(doc(alice.firestore(), `checkoutSessions/${CHECKOUT_SESSION_ID}`)),
    );
  });

  await run('checkoutSessions: a signed-in non-admin reading a NONEXISTENT id is denied (no `resource == null` branch - deliberate, unlike orders/payments)', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      getDoc(doc(alice.firestore(), 'checkoutSessions/does-not-exist')),
    );
  });

  await run('checkoutSessions: an admin reading a NONEXISTENT id still succeeds (isAdmin() short-circuits before resource.data)', async () => {
    await testEnv.clearFirestore();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertSucceeds(
      getDoc(doc(admin.firestore(), 'checkoutSessions/does-not-exist')),
    );
  });

  console.log('stripeEvents/{eventId} - Phase 8.13.3 (server-only webhook ledger)');

  async function seedStripeEvent() {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'stripeEvents/evt_test_1'), {
        eventId: 'evt_test_1',
        type: 'payment_intent.succeeded',
        livemode: false,
        paymentIntentId: 'pi_test_1',
        checkoutSessionId: 'cs_test_1',
        outcome: 'finalized',
        processedAt: serverTimestamp(),
      });
    });
  }

  await run('stripeEvents: a signed-in customer cannot read the webhook ledger', async () => {
    await testEnv.clearFirestore();
    await seedStripeEvent();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(getDoc(doc(alice.firestore(), 'stripeEvents/evt_test_1')));
  });

  await run('stripeEvents: a superAdmin cannot read the webhook ledger either', async () => {
    await testEnv.clearFirestore();
    await seedStripeEvent();
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    await assertFails(getDoc(doc(admin.firestore(), 'stripeEvents/evt_test_1')));
  });

  await run('stripeEvents: an unauthenticated client cannot read the webhook ledger', async () => {
    await testEnv.clearFirestore();
    await seedStripeEvent();
    const anon = testEnv.unauthenticatedContext();
    await assertFails(getDoc(doc(anon.firestore(), 'stripeEvents/evt_test_1')));
  });

  await run('stripeEvents: no client (customer, superAdmin, anon) can create / update / delete a ledger entry', async () => {
    await testEnv.clearFirestore();
    await seedStripeEvent();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    const admin = testEnv.authenticatedContext('admin-uid', {
      email: 'admin@example.com',
      role: 'superAdmin',
    });
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      setDoc(doc(alice.firestore(), 'stripeEvents/evt_client'), { type: 'x' }),
    );
    await assertFails(
      setDoc(doc(admin.firestore(), 'stripeEvents/evt_admin'), { type: 'x' }),
    );
    await assertFails(
      setDoc(doc(anon.firestore(), 'stripeEvents/evt_anon'), { type: 'x' }),
    );
    await assertFails(
      updateDoc(doc(admin.firestore(), 'stripeEvents/evt_test_1'), { outcome: 'tampered' }),
    );
    await assertFails(
      deleteDoc(doc(admin.firestore(), 'stripeEvents/evt_test_1')),
    );
  });

  console.log('catch-all - other collections');

  await run('any other collection is denied by the catch-all rule', async () => {
    // 'orders'/'cart' stopped being catch-all stand-ins at Phase 8.9/8.10, and
    // 'checkoutSessions' got its real (read-only) block in Phase 8.13.1 - use
    // a genuinely unmapped collection name here.
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), 'unmappedCollection/some-item'), { name: 'x' }),
    );
  });

  await run('an arbitrary unknown collection is denied for read and write (catch-all breadth)', async () => {
    await testEnv.clearFirestore();
    const alice = testEnv.authenticatedContext(ALICE, { email: ALICE_EMAIL });
    await assertFails(
      setDoc(doc(alice.firestore(), 'analyticsEvents/e1'), { kind: 'tap' }),
    );
    await assertFails(getDoc(doc(alice.firestore(), 'analyticsEvents/e1')));
  });

  await run('an unauthenticated client is denied on an unknown collection', async () => {
    await testEnv.clearFirestore();
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      setDoc(doc(anon.firestore(), 'unmappedCollection/x'), { name: 'x' }),
    );
  });

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} rules tests passed.`);
  if (failed.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error('Rules test runner crashed:', err);
  process.exitCode = 1;
});
