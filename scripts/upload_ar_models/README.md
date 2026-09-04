# Room-AR GLB upload tool (Phase 9.2 R10)

Developer-only, local-only. Uploads **exactly the four physically-approved
Room-AR GLBs** to their versioned Firebase Storage object paths:

```
products/luna-accent-chair/ar/model-v1.glb
products/glass-coffee-table/ar/model-v1.glb
products/modern-table-lamp/ar/model-v1.glb
products/luna-3-seater-sofa/ar/model-v1.glb
```

and **nothing else**. It never writes Firestore, never deletes a Storage
object, never runs the seed script. Mirrors `scripts/migrate_product_images/`
(Admin SDK, `--project` guard, dry-run default).

## Source of truth

The `AR_MODEL_ALLOWLIST` in `lib.mjs` is the exact four-item allowlist:
canonical source path (`_ar_assets/candidates/*_normalized.glb`), destination
path (identical to `RoomArProductManifest`), expected SHA-256 (tracker
§2.4–2.8), version + W/D/H metres, and content-type / cache-control.

## Requirements

- Node.js (already required by `firebase-tools`)
- `gcloud auth application-default login` **or** `GOOGLE_APPLICATION_CREDENTIALS`
  — the same credential every script in `scripts/` uses.

## Running

```bash
cd scripts/upload_ar_models
npm install
npm test              # unit tests, no live Firebase
node upload_ar_models.mjs          # DRY RUN (default) — no writes
```

The dry run:
1. preflights all four source files — exists, non-empty, ≤ 12 MB, GLB magic
   bytes, **SHA-256 exactly equals** the allowlist value;
2. preflights all four destinations — `absent` / `identical` (same bytes +
   metadata → will skip) / `conflict` (different bytes → **the whole run
   aborts**, nothing is overwritten);
3. prints an `UPLOAD` / `SKIP` / `BLOCK` line per product and exits. No writes.

### Live upload (developer, after review)

```bash
node upload_ar_models.mjs --apply --project=twin-ar-d4d75
```

Refuses to start unless `--project` is exactly `twin-ar-d4d75`. Aborts the
whole run (zero uploads) if any source is missing/mismatched or any
destination conflicts. Uploads only `absent` objects, **create-only**
(`ifGenerationMatch: 0` — a race that created the object first fails the
upload rather than clobbering it), sets `contentType: model/gltf-binary`,
`cacheControl: public, max-age=31536000, immutable`, and custom metadata
(`twinArArModelSha256` / `…Version` / `…WidthM` / `…DepthM` / `…HeightM` /
`…ScaleContract`). Writes `results/upload-<timestamp>.json` — the machine-
readable report plus a rollback inventory (the objects this run created).

### Rollback

The tool never deletes. To roll back a live upload, delete exactly the
objects listed in the run's `results/upload-*.json` `rollbackInventory` via
the Firebase Console or `gsutil rm`, using the recorded `generation`.
