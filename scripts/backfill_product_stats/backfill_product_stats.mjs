// TWin AR — Phase 9.3 "Dynamic Home Content" Stage 2 backfill.
//
// Developer-only, local-only. NOT Flutter app code, NOT a Cloud Function.
//
// Recompute-from-source backfill of the server-only `productStats/{productId}`
// Home ordering aggregates:
//   - `unitsSold`      = Σ purchased quantity across every NON-cancelled order
//   - `favoriteCount`  = number of `users/*/favorites/*` docs for that product
// and the private `productStats/{productId}/favoriteVoters/{uid}` guard docs
// (so the Cloud Function triggers' future increments/decrements stay exact).
//
// SAFETY:
//   * DRY RUN by default — reads only, prints a table, writes nothing.
//   * `--apply` performs the writes. Only ever writes `productStats/**` — it
//     never touches `products`, `orders`, `payments`, `users`, rules, or
//     Storage.
//   * Idempotent: it RECOMPUTES from source and `.set()`s the result (never
//     `increment`), so running it once or ten times yields the same values.
//   * `--reset-orphans` additionally zeroes any `productStats` doc for a
//     product that has no orders and no favourites (optional cleanup).
//
// Usage:
//   cd scripts/backfill_product_stats
//   npm install
//   node --test                 # unit-test the pure aggregation
//   npm run backfill            # DRY RUN against live Firestore
//   npm run backfill -- --apply # actually write (developer-gated)
//
// Requires the same Firebase Admin credential every other script in
// `scripts/` needs (see ../migrate_ar_catalogue/README.md), e.g.
//   gcloud auth application-default login
//   $env:GOOGLE_CLOUD_PROJECT = "twin-ar-d4d75"

import { cert, initializeApp, applicationDefault } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

import { computeFavoriteCounts, computeUnitsSold, mergeStats } from "./lib.mjs";

const APPLY = process.argv.includes("--apply");
const RESET_ORPHANS = process.argv.includes("--reset-orphans");
const PROJECT_ID =
  process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT || "twin-ar-d4d75";

function initAdmin() {
  const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  initializeApp({
    credential: keyPath ? cert(keyPath) : applicationDefault(),
    projectId: PROJECT_ID,
  });
  return getFirestore();
}

async function readAllOrders(db) {
  const snap = await db.collection("orders").get();
  return snap.docs.map((d) => d.data());
}

async function readAllFavorites(db) {
  const snap = await db.collectionGroup("favorites").get();
  return snap.docs
    .map((d) => ({
      productId: d.id,
      uid: d.ref.parent.parent?.id ?? "",
    }))
    .filter((f) => f.uid.length > 0);
}

async function main() {
  console.log(
    `productStats backfill — project ${PROJECT_ID} — ${APPLY ? "APPLY (writing)" : "DRY RUN (no writes)"}`,
  );
  const db = initAdmin();

  const [orders, favorites] = await Promise.all([readAllOrders(db), readAllFavorites(db)]);
  console.log(`  read ${orders.length} orders, ${favorites.length} favourite docs`);

  const unitsSold = computeUnitsSold(orders);
  const { counts: favoriteCounts, voters } = computeFavoriteCounts(favorites);
  const merged = mergeStats(unitsSold, favoriteCounts);

  console.log("\n  productId                         unitsSold  favoriteCount");
  console.log("  ------------------------------------------------------------");
  for (const [productId, s] of [...merged.entries()].sort()) {
    console.log(
      `  ${productId.padEnd(32)}  ${String(s.unitsSold).padStart(9)}  ${String(s.favoriteCount).padStart(13)}`,
    );
  }
  console.log(`\n  ${merged.size} productStats docs, ${voters.length} favoriteVoters guard docs`);

  if (!APPLY) {
    console.log("\n  DRY RUN — nothing written. Re-run with --apply to write.");
    return;
  }

  // ---- writes (productStats/** only) ----
  let statsWritten = 0;
  for (const [productId, s] of merged) {
    await db.doc(`productStats/${productId}`).set(
      {
        unitsSold: s.unitsSold,
        favoriteCount: s.favoriteCount,
        updatedAt: FieldValue.serverTimestamp(),
        backfilledAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    statsWritten++;
  }
  let votersWritten = 0;
  for (const { productId, uid } of voters) {
    await db
      .doc(`productStats/${productId}/favoriteVoters/${uid}`)
      .set({ at: FieldValue.serverTimestamp() }, { merge: true });
    votersWritten++;
  }

  if (RESET_ORPHANS) {
    const existing = await db.collection("productStats").get();
    for (const d of existing.docs) {
      if (!merged.has(d.id)) {
        await d.ref.set(
          { unitsSold: 0, favoriteCount: 0, updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
        console.log(`  reset orphan productStats/${d.id} to zero`);
      }
    }
  }

  console.log(`\n  APPLIED — ${statsWritten} productStats docs, ${votersWritten} favoriteVoters docs.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
