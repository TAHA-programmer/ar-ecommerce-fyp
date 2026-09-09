# backfill_product_stats

Phase 9.3 "Dynamic Home Content" **Stage 2** — one-shot, recompute-from-source
backfill for the server-only `productStats/{productId}` Home ordering
aggregates.

## What it computes

| Field | Source |
|---|---|
| `unitsSold` | Σ `items[].quantity` across every `orders` doc whose `orderStatus != 'cancelled'` |
| `favoriteCount` | number of `users/{uid}/favorites/{productId}` docs (doc ID = productId) |
| `productStats/{productId}/favoriteVoters/{uid}` guard docs | one per existing favourite, so the `adjustFavoriteCount` trigger's future ± 1 stays exact |

## Safety

- **DRY RUN by default.** Reads only, prints a table, writes nothing.
- `--apply` performs the writes and **only ever writes `productStats/**`** —
  never `products`, `orders`, `payments`, `users`, `firestore.rules`,
  indexes, Cloud Functions, or Storage.
- **Idempotent.** It recomputes from source and `.set()`s the result (never
  `FieldValue.increment`), so running it once or many times yields the same
  values.
- `--reset-orphans` (optional) additionally zeroes any `productStats` doc for
  a product that currently has no orders and no favourites.

## Run

```
cd scripts/backfill_product_stats
npm install
node --test                     # unit-test the pure aggregation (no creds)
npm run backfill                # DRY RUN against live Firestore
npm run backfill -- --apply     # write (developer-gated)
```

Credentials: same as every other `scripts/` tool — see
`../migrate_ar_catalogue/README.md`. In short:

```
gcloud auth application-default login
$env:GOOGLE_CLOUD_PROJECT = "twin-ar-d4d75"
```

## Status

Authored for Stage 2. **NOT run in `--apply` mode.** It is only executed
against live data as part of Stage 4 (verification + deploy), after the
Cloud Function triggers and `firestore.rules` additions are deployed, and
with explicit developer approval.
