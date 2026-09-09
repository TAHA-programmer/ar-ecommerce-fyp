// TWin AR — Phase 9.2 R20 dependency audit: read-only live-data check.
//
// Developer-only, local-only. NOT Flutter app code, NOT a Cloud Function.
//
// Answers exactly one question, safely: does any live `products` document
// still carry a non-null legacy top-level `arModelAssetPath` or `arScale`
// field? (Do NOT confuse these with the CURRENT, valid Room-AR metadata
// contract's own scale value inside `arMetadata`/`arWidthM`/etc. — this
// script only ever reads the two legacy top-level fields, never the current
// contract.)
//
// This is the blocker `16_PHASE_9_2_ROOM_AR_TRACKER.md` §33.6/§34.2/§35
// record for R20. First cut (`arScale`/`arModelAssetPath` non-null anywhere
// = unsafe) turned out to be too coarse: `ProductArMetadata.toFirestoreFields()`
// (product_ar_metadata.dart) ALSO unconditionally writes the same `arScale`
// Firestore key whenever a product has a real Room-AR contract, independent
// of the legacy top-level Dart field, and the mapper applies that write
// AFTER the legacy one so it wins. So a non-null `arScale` on a document
// that also has `arModelStoragePath` set is the CURRENT contract's own
// value, not legacy drift — removing the legacy Dart fields would not stop
// it from being written correctly. Only a non-null `arScale` with NO
// `arModelStoragePath` (or any non-null `arModelAssetPath`, which nothing
// modern ever writes) is a genuine legacy value the removal would silently
// stop persisting on that document's next save. This script now reports
// that distinction explicitly instead of flagging every non-null `arScale`
// as unsafe.
//
// This script performs ONLY Firestore READS (`.get()`) — it has no delete,
// update, or Storage capability at all; there is nothing to run "--apply"
// or "--confirm" on. Safe to run any number of times.
//
// Usage (PowerShell or any shell):
//   cd scripts/audit_legacy_ar_fields
//   npm install
//   npm run audit
//
// Requires the SAME Firebase Admin credential every other script in
// scripts/ already needs — see ../migrate_ar_catalogue/README.md step 3, or
// in short:
//   gcloud auth application-default login
// (or set GOOGLE_APPLICATION_CREDENTIALS to a service-account key path).
//
// Prefer not to set up a credential at all? Use the Firebase Console
// instead — see README.md in this folder for the equivalent point-and-click
// steps, which are exactly as safe (read-only) and need no local setup.

import admin from 'firebase-admin';

const CONFIRMED_PROJECT_ID = 'twin-ar-d4d75';

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: CONFIRMED_PROJECT_ID,
  });
  const db = admin.firestore();

  console.log(`Auditing live 'products' collection on ${CONFIRMED_PROJECT_ID} `
    + '(read-only — no writes, no deletes, no Storage calls)...\n');

  const snapshot = await db.collection('products').get();

  // `ProductArMetadata.toFirestoreFields()` (product_ar_metadata.dart) ALSO
  // unconditionally writes the same `arScale` key whenever a product has a
  // real Room-AR contract (`arMetadata != null` — recognisable live by a
  // non-null `arModelStoragePath`), independently of the legacy top-level
  // field, and `product_firestore_mapper.dart` applies that write AFTER the
  // legacy one so it wins. So a non-null live `arScale` on a document that
  // ALSO has `arModelStoragePath` set is not legacy drift at all — it is the
  // current contract's own authoritative scale, which keeps being written
  // correctly by `arMetadata` regardless of whether the legacy Dart field
  // exists. Only a non-null `arScale` with NO `arModelStoragePath` (or a
  // non-null `arModelAssetPath`, which nothing modern ever writes) is a
  // genuine legacy value the removal would stop persisting. This script
  // reports both so that distinction is explicit, not assumed.
  const withLegacyAssetPath = [];
  const withLegacyScale = [];
  const withLegacyScaleButHasContract = [];

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const hasContract = data.arModelStoragePath !== undefined && data.arModelStoragePath !== null;
    if (data.arModelAssetPath !== undefined && data.arModelAssetPath !== null) {
      withLegacyAssetPath.push({ id: doc.id, value: data.arModelAssetPath });
    }
    if (data.arScale !== undefined && data.arScale !== null) {
      const entry = { id: doc.id, value: data.arScale, hasContract };
      withLegacyScale.push(entry);
      if (hasContract) withLegacyScaleButHasContract.push(entry);
    }
  }

  const genuineLegacyScale = withLegacyScale.filter((p) => !p.hasContract);

  console.log(`Total products inspected: ${snapshot.size}`);
  console.log(`Products with non-null legacy arModelAssetPath: ${withLegacyAssetPath.length}`);
  for (const p of withLegacyAssetPath) console.log(`  - ${p.id}: ${JSON.stringify(p.value)}`);
  console.log(`Products with non-null arScale: ${withLegacyScale.length}`);
  for (const p of withLegacyScale) {
    console.log(`  - ${p.id}: ${JSON.stringify(p.value)}`
      + (p.hasContract
        ? '  [has arModelStoragePath — current contract value, NOT legacy drift]'
        : '  [NO arModelStoragePath — genuine legacy value]'));
  }
  console.log(`  -> of these, ${withLegacyScaleButHasContract.length} are explained by a live `
    + `arMetadata contract (safe); ${genuineLegacyScale.length} are genuine legacy values with `
    + 'no contract behind them.');

  const clear = withLegacyAssetPath.length === 0 && genuineLegacyScale.length === 0;
  console.log(
    '\n' + (clear
      ? 'RESULT: no genuine legacy value found (arModelAssetPath is null '
        + 'everywhere; every non-null arScale is explained by a live arMetadata '
        + 'contract that independently re-writes it on every save) — removing '
        + 'the two legacy Dart model fields (ProductModel.arModelAssetPath / '
        + 'arScale) + the mapper\'s matching legacy read/write lines is safe '
        + 'with respect to live data. (The `arScale` Firestore KEY itself is '
        + 'NOT removed — ProductArMetadata keeps reading/writing it for '
        + 'products with a contract; only the redundant legacy Dart-model '
        + 'view of that key goes away.)'
      : 'RESULT: at least one live document has a genuine legacy value with no '
        + 'arMetadata contract behind it — do NOT remove the Dart fields yet. '
        + 'Either explicitly migrate/clear those specific fields in a one-time, '
        + 'backed-up, authorized script first, or leave the fields exactly as '
        + 'they are (inert, read-only-preserve) indefinitely — both are safe; '
        + 'only removing the Dart fields without doing one of these is not.'),
  );

  process.exit(0);
}

main().catch((err) => {
  console.error('Audit failed:', err.message);
  process.exit(1);
});
