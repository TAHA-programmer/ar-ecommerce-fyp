# Room-AR catalogue recast (Phase 9.2 R13/R14)

Developer-only, local-only. Recasts **the four physically-approved Room-AR
products** to their final catalogue truth and writes their production `ar*`
metadata (and, for the sofa, the verified customer gallery) — in **one genuine
Firestore transaction**. A preflight, concurrency or runtime failure leaves
all four documents unchanged. Never `.set()`, never a document delete, never a
reseed.

| ID | title | material spec | dimensions spec | AR (`ar*`) | images |
|---|---|---|---|---|---|
| `luna-accent-chair` | *(unchanged)* | *(unchanged)* | *(unchanged)* | `model-v1.glb`, 0.70 × 0.72 × 0.82 | *(unchanged)* |
| `glass-coffee-table` | **Round Wood Coffee Table** | **Solid oak and oak veneer** | **Ø 90 cm • H 42 cm** | 0.90 × 0.90 × 0.42 | *(unchanged)* |
| `modern-table-lamp` | *(unchanged)* | **Speckled ceramic, ivory linen shade, satin brass fitting** | **H 45 cm • W 20 cm • D 20 cm** | 0.20 × 0.20 × 0.45 | *(unchanged)* |
| `luna-3-seater-sofa` | **Luna Right-Chaise Sectional Sofa** *(no seat number)* | **Warm-ivory woven linen** | **W 265 cm • D 165 cm • H 82 cm** | 2.65 × 1.65 × 0.82 | **6 validated-GLB studio renders** (Stage A) |

`experienceType` is validated (`roomAr` on all four) but **not written**. `id`,
`price`, `stock`, `category`, ownership, timestamps and unrelated media are
untouched.

## Per-field protection

Every controlled field — `title`, `description`, `specifications`,
`mainImage`, `galleryMedia`, and the `ar*` group — must currently be either a
**recognised legacy state** or already exactly equal to its **final target**.
Anything unexpected, hand-edited, partially migrated or malformed blocks the
**whole** commit with a field-level diagnostic (e.g. `ar* metadata is
partially populated — present: arModelSha256; missing: …`). Nothing is
silently overwritten.

### The `ar*` group and the legacy `arScale` mirror

`arScale` is **not** a new Phase 9.2 field. It is a pre-existing "Admin AR &
Media" mirror that `product_firestore_mapper.toFirestoreMap()` has always
written for **every** product — as an explicit `null` when unset. So every
legitimate live `products/{id}` document already carries `arScale: null` (and
`arModelAssetPath: null`) while the eight genuinely-new keys
(`arModelStoragePath`, `arModelFormat`, `arModelVersion`, `arModelSha256`,
`arWidthM`, `arDepthM`, `arHeightM`, `arScaleContract`) are absent.

The recognised **legacy** `ar*` state is therefore: **all eight new keys
absent, and `arScale` absent or `null`.** The recast writes all nine keys
together (flipping `arScale` `null → 1.0`); rollback restores `arScale` to
`null` (the key is kept, never deleted) and removes the eight new keys.

Still blocked as genuine drift: any of the eight new keys present without the
rest (`partially populated — present: …`), a fully-populated group whose values
don't match the target, or `arScale` holding an unexpected **non-null** value
with no contract behind it (`arScale=… set without the rest of the contract`).

**Coherent product state only.** Within one product the controlled fields must
be *all* legacy or *all* exactly final (a field whose legacy value already
equals its final target — e.g. the lamp title — is compatible with either). A
product that mixes a strictly-legacy field with a strictly-final one is a
partially hand-migrated document and blocks with a `mixed legacy/final field
states` diagnostic for manual review. Different products may independently be
all-legacy or all-final.

## The transaction re-checks all four documents

`commitRecast` is handed **every** target document's plan — the ones that would
change *and* the ones already final. Inside the transaction each is re-read and
re-checked: `updateTime` must still equal the preflight value, it must not be
blocked, and its recomputed status must equal its preflight status. Drift in
**any** of the four — a concurrent edit, a field that moved, a product another
run recast — throws `MigrationAbort` before a single `tx.update` is buffered,
so the transaction commits nothing. Only the `needs-recast` documents are
written.

## Two stages

1. **Stage A — `../upload_sofa_gallery/`** uploads the six sofa renders to
   `products/luna-3-seater-sofa/images/img-<sha16>.png`. Storage only — no
   Firestore, no catalogue change.
2. **Stage B — this tool.** The sofa's image recast is *storage-gated*: preflight
   independently `statObject()`s all six paths and requires, for every object,
   `exists`, an exact non-null byte size, an exact non-null
   `twinArSofaGallerySha256` custom-metadata hash, and (where the stat carries
   it) `contentType: image/png`. **Missing metadata blocks the migration.**
   Until Stage A runs, the sofa blocks `sofa-gallery-not-staged`, which
   (all-or-nothing) blocks the whole run.

## Running

```bash
cd scripts/migrate_ar_catalogue
npm install
npm test                          # 33/33, no live Firebase
node migrate_ar_catalogue.mjs     # DRY RUN — exact before/after + gallery status, zero writes
```

### Live apply (developer, after review + supervisor sign-off + Stage A)

```bash
node migrate_ar_catalogue.mjs --apply --project=twin-ar-d4d75 --dimensions-approved
```

Refuses unless `--project` is exactly `twin-ar-d4d75` **and**
`--dimensions-approved` (supervisor sign-off on the published W/D/H). Runs
`commitRecast` inside one `db.runTransaction(…, { maxAttempts: 3 })`: re-reads
+ re-validates **all four** target documents (updateTime precondition + full
field re-check + status must equal preflight), buffers every `tx.update`,
commits once. Writes `backups/backup-<timestamp>.json` (before-state) then
re-writes it with each doc's post-commit `updateTime`.

### Rollback (guarded, atomic)

```bash
node migrate_ar_catalogue.mjs --rollback=backups/<file>.json                          # preview
node migrate_ar_catalogue.mjs --rollback=backups/<file>.json --apply --project=twin-ar-d4d75
```

`commitRollback` (one transaction) restores exactly the written keys, and
**only** when every document is still in the exact post-migration state
(`updateTime` == the recorded post-commit value AND every written field == its
final target). A later or unexpected edit → `MigrationAbort`, nothing rolls
back. `ar*` keys (absent before the migration) are deleted, not left stray.

`validateBackup` rejects a corrupted or tampered backup artifact before any
transaction runs: only the four known product IDs, no duplicate product
entries, no duplicate `writtenKeys`, every written key in that product's exact
migration-controlled allowlist, `before` / `finalTarget` / `writtenKeys` key
sets matching exactly, a valid absent-sentinel shape, and a finalised backup
(post-apply `updateTime` present). A backup that was never finalised (the
migration didn't complete) is refused.
