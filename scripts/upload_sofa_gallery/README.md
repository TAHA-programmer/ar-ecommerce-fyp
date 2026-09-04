# Sofa customer-gallery uploader (Phase 9.2 R14 — Stage A)

Developer-only, local-only. Uploads the **six approved Luna Right-Chaise
Sectional Sofa studio renders** (from the validated GLB) to their
deterministic Storage paths:

```
products/luna-3-seater-sofa/images/img-<sha16>.png   × 6
```

content-hashed object names (Phase 8.7.1 convention), `image/png`,
**create-only** (`ifGenerationMatch: 0`), each carrying the
`twinArSofaGallerySha256` custom metadata Stage B is gated on. An existing
object blocks the whole run (never overwritten) unless it is a **complete**
match — byte-identical (md5 + size) **and** `image/png` **and** carrying the
correct `twinArSofaGallerySha256`. An object with the right bytes but missing
or wrong metadata is a `conflict`: it is not reported as staged and this run
neither skips nor overwrites it (fix the metadata in the console, or delete
the object and re-run). **Never touches Firestore** — Stage B
(`../migrate_ar_catalogue/`) is what makes these renders customer-visible, and
only after it independently re-verifies every object.

| order | source render | role | Storage object |
|---|---|---|---|
| 0 | `sofa_r_v1_cat_3q.png` | main + gallery | `img-d8317097149c3f43.png` |
| 1 | `sofa_r_v1_front.png` | gallery | `img-3403a887f40799f6.png` |
| 2 | `sofa_r_v1_opp_3q.png` | gallery | `img-2b280dd8bdb2077c.png` |
| 3 | `sofa_r_v1_left_side.png` | gallery | `img-0bc14afc44b19d36.png` |
| 4 | `sofa_r_v1_right_side.png` | gallery | `img-ed7d709f1f16e1ac.png` |
| 5 | `sofa_r_v1_top_plan.png` | gallery | `img-cda9344a27622028.png` |

Excluded: every `sofa_cmp_*` (catalogue-comparison sheets),
`sofa_r_v1_arm_seam` / `_foot_plinth` (extreme detail crops),
`sofa_r_v1_rear` (conservatively inferred). The exact SHA-256 + byte size of
each render is baked into `sofa_gallery.mjs` and re-verified at preflight —
the tool never uploads bytes whose hash does not match.

## Running

```bash
cd scripts/upload_sofa_gallery
npm install
npm test                              # 9/9, no live Firebase
node upload_sofa_gallery.mjs          # DRY RUN — zero writes
```

### Live upload (developer)

```bash
node upload_sofa_gallery.mjs --apply --project=twin-ar-d4d75
```

Refuses unless `--project` is exactly `twin-ar-d4d75`. Aborts the whole run if
any render is missing / hash-mismatched or any destination already holds
different bytes. Writes `results/upload-<timestamp>.json` (report + rollback
inventory — the objects this run created).

**Rollback:** the tool never deletes. To undo, delete exactly the objects in
the run's `results/upload-*.json` `rollbackInventory` via the Firebase Console
or `gsutil rm`.
