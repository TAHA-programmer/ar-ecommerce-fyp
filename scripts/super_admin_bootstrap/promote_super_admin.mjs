// TWin AR — one-time Super Admin bootstrap script (Phase 8.4).
//
// Developer-only, local-only. NOT Flutter app code, NOT a Cloud Function,
// NOT reachable from the mobile app in any way. Promotes exactly one
// already-existing Firebase Auth account (created by signing up normally
// through the app, which lands it as a 'customer') to Super Admin by:
//
//   1. Setting the Firebase Auth custom claim {role: 'superAdmin'} on the
//      account's ID token.
//   2. Updating that account's users/{uid} Firestore document's `role`
//      field to 'superAdmin' (the UI-convenience mirror only — it is NOT
//      what grants access; step 1 is the real authorization boundary).
//
// See ../../scripts/super_admin_bootstrap/README.md for the full,
// step-by-step manual procedure (creating the account, finding its uid,
// configuring credentials, running this script, signing back in).
//
// Usage:
//   node promote_super_admin.mjs <uid> --confirm
//
// Requires GOOGLE_APPLICATION_CREDENTIALS to point at a service-account
// JSON key (or Application Default Credentials already configured via
// `gcloud auth application-default login` for an account with Owner/Editor
// on the twin-ar-d4d75 project). This script never reads or prints the key
// file's contents — the Admin SDK reads it directly.

import admin from 'firebase-admin';

const PROJECT_ID = 'twin-ar-d4d75';

function usageAndExit() {
  console.error('Usage: node promote_super_admin.mjs <uid> --confirm');
  console.error('');
  console.error('  <uid>       The Firebase Auth UID of the account to promote.');
  console.error('  --confirm   Required safety flag - the script refuses to run without it.');
  process.exit(1);
}

const args = process.argv.slice(2);
const confirmed = args.includes('--confirm');
const uid = args.find((a) => !a.startsWith('--'));

if (!uid || !confirmed) {
  usageAndExit();
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: PROJECT_ID,
});

async function main() {
  console.log(`Promoting uid "${uid}" to superAdmin on project "${PROJECT_ID}"...`);

  // Fail fast and clearly if the uid doesn't exist, rather than setting a
  // claim on nothing.
  const userRecord = await admin.auth().getUser(uid).catch(() => null);
  if (!userRecord) {
    console.error(`No Firebase Auth user found with uid "${uid}". Aborting - nothing was changed.`);
    process.exit(1);
  }

  await admin.auth().setCustomUserClaims(uid, { role: 'superAdmin' });
  console.log('  Custom claim {role: "superAdmin"} set.');

  const userDocRef = admin.firestore().doc(`users/${uid}`);
  const snapshot = await userDocRef.get();
  if (!snapshot.exists) {
    console.warn(
      `  WARNING: users/${uid} has no Firestore profile document yet - the ` +
        'custom claim is set (this is the real authorization boundary and is ' +
        'sufficient on its own), but the UI-mirror `role` field could not be ' +
        'updated because the document does not exist. Sign up through the app ' +
        'first (creates the profile as \'customer\'), then re-run this script ' +
        'to keep the mirror field consistent.',
    );
  } else {
    await userDocRef.update({ role: 'superAdmin' });
    console.log(`  Firestore mirror users/${uid}.role updated to "superAdmin".`);
  }

  console.log('');
  console.log(`Done. Email on this account: ${userRecord.email ?? '(none)'}`);
  console.log(
    'IMPORTANT: sign out of that account on every device (or just the one ' +
      'you will test with) and sign back in - the app only re-reads custom ' +
      'claims on a fresh ID token, not on an already-open session.',
  );
}

main().catch((err) => {
  console.error('Promotion failed:', err);
  process.exit(1);
});
