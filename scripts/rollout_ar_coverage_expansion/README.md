# Phase 9.2 coverage-expansion Room-AR rollout tool

Developer-only, local-only. Rolls out the **six** developer + supervisor-
approved GLB designs (tracker §15/§16, `18_ROOM_AR_PRODUCT_COVERAGE_MATRIX.md`
§18 v5) to their **26** coverage-expansion product ids:

```
velvet-armchair, wooden-console, marble-side-table
beige-ar-in-stock-{5,7,11,13,17,19,23}   (Beige AR Rug — shared design, 7 ids)
beige-ar-in-stock-{2,4,8,10,14,16,20,22} (Beige AR Sofa — shared design, 8 ids)
beige-ar-in-stock-{3,6,9,12,15,18,21,24} (Beige AR Vase — shared design, 8 ids)
```

For each id, in this order: **(1)** create-only Storage upload of that
group's GLB to `products/{id}/ar/model-v1.glb`, then **(2)** — only once the
object is confirmed correct — a single-document Firestore transaction that
writes that product's own `ar*` fields, after re-verifying the document
hasn't drifted since the preflight and doesn't already carry a *different*
`ar*` contract. **Never touches the original four products** (that's
`scripts/upload_ar_models/` + `scripts/migrate_ar_catalogue/`'s scope) and
never overwrites existing, different metadata — a product that already has
its own (different) `ar*` contract **blocks the whole run** rather than being
silently replaced.

## Source of truth

`SOURCE_GROUPS` in `lib.mjs`: one entry per of the six GLB designs — canonical
source path (`_ar_assets/candidates/*_chatgpt_original.glb`, git-ignored,
recovered + hash-verified per `_ar_assets/candidates/PROVENANCE.md`), expected
SHA-256, W/D/H metres, and the exact list of destination product ids sharing
that design. These values are identical to
`RoomArProductManifest.byProductId` / `kRoomArProductMetadata`'s registration
for the same 26 ids — this tool is what turns that local registration into a
live Storage object + live Firestore write.

## Requirements

- Node.js
- `gcloud auth application-default login` **or** `GOOGLE_APPLICATION_CREDENTIALS`
  — the same credential every script in `scripts/` uses.
- The six source files present under `_ar_assets/candidates/` (local-only,
  git-ignored — see `PROVENANCE.md` for how they were recovered/verified).

## Running

```bash
cd scripts/rollout_ar_coverage_expansion
npm install
npm test              # unit tests, no live Firebase, no live write of any kind
node rollout_ar_coverage_expansion.mjs        # DRY RUN (default) — no writes
```

The dry run:
1. preflights all six source files — exists, non-empty, ≤ 8 MB authoring
   budget, GLB magic bytes, **SHA-256 exactly equals** the recorded value;
2. preflights all 26 Storage destinations — `absent` / `identical` (skip) /
   `conflict` (different bytes → **the whole run aborts**);
3. preflights all 26 Firestore documents — must exist, be `experienceType:
   roomAr`, and either have no `ar*` contract yet (`absent`, safe to write),
   already have *exactly* this rollout's target contract (`identical`, skip),
   or already have a *different* one (`conflict` → **the whole run aborts,
   nothing is ever silently overwritten**);
4. prints a `READY` / `SKIP` / `BLOCK` line per product and exits. No writes.

### Live rollout (developer, after review)

```bash
node rollout_ar_coverage_expansion.mjs --apply --project=twin-ar-d4d75 --confirm-expansion-rollout
```

Both `--project=twin-ar-d4d75` and the deliberately-distinct
`--confirm-expansion-rollout` flag are required (so this tool can never be
invoked by copy-pasting `migrate_ar_catalogue`'s or `upload_ar_models`'s live
flags by mistake). Aborts the whole run (zero writes) if **any** of the 26 has
a blocking problem. Otherwise, product by product: create-only Storage
upload, then a Firestore transaction that re-checks the document is still in
its preflighted state before writing only its `ar*` fields — a failure on one
product never touches another, and a partial run is always safe to re-run
(already-correct products are skipped, not retried). Writes
`backups/backup-<timestamp>.json` (rollback inventory) and
`results/rollout-<timestamp>.json` (full report).

### Rollback

```bash
node rollout_ar_coverage_expansion.mjs --rollback=backups/<file>.json                                  # dry run
node rollout_ar_coverage_expansion.mjs --rollback=backups/<file>.json --apply --project=twin-ar-d4d75   # live
```

Restores exactly the `ar*` fields this rollout wrote, per product, **only**
for a document whose `arModelStoragePath` still matches what this tool wrote
(i.e. nothing else has changed it since) — a product that was independently
edited afterward is skipped with a reason, never force-restored. The tool
never deletes the uploaded Storage objects on rollback (mirrors
`upload_ar_models/`'s stance) — delete them manually via the Firebase Console
or `gsutil rm` if a full undo is needed.
