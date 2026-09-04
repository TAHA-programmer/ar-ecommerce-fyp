// TWin AR — Phase 9.2 R13/R14: Room-AR catalogue recast — core logic.
//
// Pure / injectable functions only (no firebase-admin here) so this module is
// unit-testable with fake Firestore + Storage adapters. The CLI
// (migrate_ar_catalogue.mjs) wires it to the real Admin SDK.
//
// Scope: for the FOUR physically-approved Room-AR products only, writes the
// final catalogue truth — corrected title / description / material + dimension
// specifications, plus the production `ar*` metadata, plus (sofa only) the
// verified customer gallery — in ONE genuine Firestore transaction covering
// every intended document. A preflight, concurrency or runtime failure leaves
// ALL catalogue documents unchanged. Never `.set()`, never a reseed, never a
// delete of a document.
//
// Every controlled field is protected: its current value must be either an
// explicitly recognised legacy state OR already exactly equal to its final
// target. Anything unexpected, hand-edited, partially migrated or malformed
// blocks the entire commit with a field-level diagnostic.

import {
  SOFA_GALLERY,
  SOFA_IMAGE_CONTENT_TYPE,
  objectPathFor,
  sofaImageFields,
} from '../upload_sofa_gallery/sofa_gallery.mjs';

export const CONFIRMED_PROJECT_ID = 'twin-ar-d4d75';
export const BACKUP_SCHEMA_VERSION = 'ar-catalogue-recast/1';

export const AR_PRODUCT_IDS = [
  'luna-accent-chair',
  'glass-coffee-table',
  'modern-table-lamp',
  'luna-3-seater-sofa',
];

const SCALE_CONTRACT = 'twin-ar/scale-contract-9.2.2';

// `arScale` is NOT a new Phase 9.2 field — it is a pre-existing legacy "Admin
// AR & Media" mirror that `product_firestore_mapper.toFirestoreMap()` has
// always written for EVERY product, as an explicit `null` when unset. So every
// legitimate live `products/{id}` document already carries `arScale: null`
// while the eight genuinely-new `ar*` keys are absent. That is the recognised
// pre-migration state, not a half-populated contract. The classifier below
// treats these keys as "absent-or-null ⇒ still legacy"; any OTHER value (or
// any of the eight new keys being present) is real partial/conflicting drift.
export const AR_LEGACY_MIRROR_KEYS = ['arScale'];

/** A preflight / concurrency / integrity failure. Thrown inside the
 *  transaction to abort it with zero writes; caught + printed by the CLI. */
export class MigrationAbort extends Error {
  constructor(message) {
    super(message);
    this.name = 'MigrationAbort';
  }
}

// ── recognised legacy strings ───────────────────────────────────────────────

const GENERIC_FURNITURE_DESC =
  'Elevate your space with this beautiful and functional piece. ' +
  'Crafted with attention to detail and high-quality materials.';
const CHAIR_DESC =
  'The Luna Accent Chair brings a touch of mid-century modern elegance to ' +
  "your living space. With its sculptural silhouette, plush velvet " +
  "upholstery, and tapered brass legs, it's designed for both comfort and " +
  'statement-making style.';

const spec = (label, value) => ({ label, value });

/** The 9 flat `ar*` keys, matching `ProductArMetadata.toFirestoreFields()`. */
function arTarget(storagePath, sha256, widthM, depthM, heightM) {
  return {
    arModelStoragePath: storagePath,
    arModelFormat: 'glb',
    arModelVersion: '1',
    arModelSha256: sha256,
    arWidthM: widthM,
    arDepthM: depthM,
    arHeightM: heightM,
    arScale: 1.0,
    arScaleContract: SCALE_CONTRACT,
  };
}

// sofa image legacy states — the pre-8.7.1 asset ref and the post-8.7.1
// migrated network ref (deterministic: content hash of best_seller_sofa.png).
const SOFA_LEGACY_ASSET_REF = {
  path: 'assets/images/home/best_sellers/best_seller_sofa.png',
  source: 'asset',
  altText: '',
};
const SOFA_LEGACY_NETWORK_REF = {
  path:
    'https://firebasestorage.googleapis.com/v0/b/twin-ar-d4d75.firebasestorage.app/o/' +
    encodeURIComponent('products/luna-3-seater-sofa/images/img-2d4dab2631fcc39a.png') +
    '?alt=media',
  source: 'network',
  altText: '',
};
const sofaLegacyGallery = (ref) => [ref, ref, ref, ref, ref];

const SOFA_IMAGE_FIELDS = sofaImageFields();

/**
 * The recast per product. `validate` = fields checked but never written.
 * `fields` = controlled fields: `{ accept: [...legacy states], target, deep? }`
 * or `{ arGroup: true, target }` or `{ storageObjects: [...], accept, target,
 * deep }`.
 */
export const RECAST = [
  {
    productId: 'luna-accent-chair',
    validate: {
      experienceType: ['roomAr'],
      title: ['Luna Accent Chair'],
      description: [CHAIR_DESC],
      specifications: {
        deep: true,
        accept: [
          [
            spec('Material', 'Premium Fabric, Solid Wood'),
            spec('Dimensions', 'W 70 cm • D 72 cm • H 82 cm'),
          ],
        ],
      },
    },
    fields: {
      ar: {
        arGroup: true,
        target: arTarget(
          'products/luna-accent-chair/ar/model-v1.glb',
          'd67c68f823d06881ec1aabf7f8ca6f0128f1016483ea0307f5c2ecef66b3cf94',
          0.7,
          0.72,
          0.82,
        ),
      },
    },
  },
  {
    productId: 'glass-coffee-table',
    validate: { experienceType: ['roomAr'] },
    fields: {
      title: { accept: ['Glass Coffee Table'], target: 'Round Wood Coffee Table' },
      description: {
        accept: [GENERIC_FURNITURE_DESC],
        target:
          'A round coffee table with a warm oak-finish top on a sculptural ' +
          'pedestal base — a grounded centrepiece for the living room.',
      },
      specifications: {
        deep: true,
        accept: [[]],
        target: [
          spec('Material', 'Solid oak and oak veneer'),
          spec('Dimensions', 'Ø 90 cm • H 42 cm'),
        ],
      },
      ar: {
        arGroup: true,
        target: arTarget(
          'products/glass-coffee-table/ar/model-v1.glb',
          'd10f32a7373d84031d3e51b8e9770610f514f62fa56110608852f1640ab7a727',
          0.9,
          0.9,
          0.42,
        ),
      },
    },
  },
  {
    productId: 'modern-table-lamp',
    validate: { experienceType: ['roomAr'] },
    fields: {
      title: { accept: ['Modern Table Lamp'], target: 'Modern Table Lamp' },
      description: {
        accept: [GENERIC_FURNITURE_DESC],
        target:
          'A modern table lamp with a pierced ceramic base and a warm ivory ' +
          'linen drum shade, finished with a satin brass fitting.',
      },
      specifications: {
        deep: true,
        accept: [
          [
            spec('Material', 'Brass & Glass'),
            spec('Dimensions', 'H 45 cm • W 20 cm'),
            spec('Bulb Type', 'E27 LED'),
          ],
        ],
        target: [
          spec(
            'Material',
            'Speckled ceramic, ivory linen shade, satin brass fitting',
          ),
          spec('Dimensions', 'H 45 cm • W 20 cm • D 20 cm'),
          spec('Bulb Type', 'E27 LED'),
        ],
      },
      ar: {
        arGroup: true,
        target: arTarget(
          'products/modern-table-lamp/ar/model-v1.glb',
          'ee417ead58e72de9518358288f089bad272779c190125e01ac372fcfc16bb565',
          0.2,
          0.2,
          0.45,
        ),
      },
    },
  },
  {
    productId: 'luna-3-seater-sofa',
    validate: { experienceType: ['roomAr'] },
    fields: {
      title: {
        accept: ['Luna 3-Seater Sofa'],
        target: 'Luna Right-Chaise Sectional Sofa',
      },
      description: {
        accept: [GENERIC_FURNITURE_DESC],
        target:
          'A right-hand chaise sectional in a warm-ivory woven linen, with ' +
          'low track arms and generously filled seat and back cushions. The ' +
          'extended chaise gives you room to stretch out — it comfortably ' +
          'seats four.',
      },
      specifications: {
        deep: true,
        accept: [
          [
            spec('Material', 'Premium Fabric'),
            spec('Dimensions', 'W 200 cm • D 85 cm • H 82 cm'),
          ],
        ],
        target: [
          spec('Material', 'Warm-ivory woven linen'),
          spec('Dimensions', 'W 265 cm • D 165 cm • H 82 cm'),
        ],
      },
      ar: {
        arGroup: true,
        target: arTarget(
          'products/luna-3-seater-sofa/ar/model-v1.glb',
          'efd400046b265fd49d8d2b0382d378d230d625cb879740a3ef0697ca86c0d187',
          2.65,
          1.65,
          0.82,
        ),
      },
      mainImage: {
        deep: true,
        accept: [SOFA_LEGACY_ASSET_REF, SOFA_LEGACY_NETWORK_REF],
        target: SOFA_IMAGE_FIELDS.mainImage,
        storageObjects: SOFA_GALLERY.map((i) => ({
          objectPath: objectPathFor(i),
          sha256: i.expectedSha256,
          sizeBytes: i.expectedSizeBytes,
          contentType: SOFA_IMAGE_CONTENT_TYPE,
        })),
      },
      galleryMedia: {
        deep: true,
        accept: [
          sofaLegacyGallery(SOFA_LEGACY_ASSET_REF),
          sofaLegacyGallery(SOFA_LEGACY_NETWORK_REF),
        ],
        target: SOFA_IMAGE_FIELDS.galleryMedia,
        storageObjects: SOFA_GALLERY.map((i) => ({
          objectPath: objectPathFor(i),
          sha256: i.expectedSha256,
          sizeBytes: i.expectedSizeBytes,
          contentType: SOFA_IMAGE_CONTENT_TYPE,
        })),
      },
    },
  },
];

export const recastById = Object.fromEntries(RECAST.map((r) => [r.productId, r]));

// ── comparison helpers ──────────────────────────────────────────────────────

export function deepEqual(a, b) {
  if (a === b) return true;
  if (a == null || b == null) return a === b;
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((x, i) => deepEqual(x, b[i]));
  }
  if (typeof a === 'object' && typeof b === 'object') {
    const ka = Object.keys(a);
    const kb = Object.keys(b);
    if (ka.length !== kb.length) return false;
    return ka.every((k) => deepEqual(a[k], b[k]));
  }
  return false;
}

/** Sentinel: this key did not exist before — delete it on rollback. */
export const DELETE_FIELD = Symbol('DELETE_FIELD');
const ABSENT = Symbol('ABSENT');

function currentValue(data, key) {
  return Object.prototype.hasOwnProperty.call(data, key) ? data[key] : ABSENT;
}

/**
 * Classifies one controlled field.
 * → `{ state: 'legacy' | 'final' | 'drift', detail? }`.
 */
function classifyField(data, name, fieldSpec, storageVerification) {
  if (fieldSpec.arGroup) {
    const keys = Object.keys(fieldSpec.target);
    const has = (k) => Object.prototype.hasOwnProperty.call(data, k);
    const mirrorKeys = AR_LEGACY_MIRROR_KEYS.filter((k) => keys.includes(k));
    const newKeys = keys.filter((k) => !mirrorKeys.includes(k));
    const missing = keys.filter((k) => !has(k));

    // Fully populated → either exactly final, or a value-mismatch drift.
    if (missing.length === 0) {
      const bad = keys.filter((k) => !deepEqual(data[k], fieldSpec.target[k]));
      if (bad.length === 0) return { state: 'final' };
      return {
        state: 'drift',
        detail:
          `ar* metadata present but ${bad.length} field(s) mismatch: ` +
          bad
            .map((k) => `${k}=${JSON.stringify(data[k])} (want ${JSON.stringify(fieldSpec.target[k])})`)
            .join(', '),
      };
    }

    // Not fully populated. The ONLY acceptable pre-migration state is the
    // recognised legacy one: every genuinely-new `ar*` key absent, and every
    // legacy mirror key (`arScale`) absent or explicitly `null`. Anything else
    // — a new key half-written, or `arScale` holding an unexpected non-null
    // value without the rest of the contract — is real drift and blocks.
    const presentNew = newKeys.filter(has);
    const mirrorDirty = mirrorKeys.filter((k) => has(k) && data[k] !== null);
    if (presentNew.length === 0 && mirrorDirty.length === 0) {
      return { state: 'legacy' };
    }

    const details = [];
    if (presentNew.length > 0) {
      details.push(
        `ar* metadata is partially populated — present: ${presentNew.join(', ')}; ` +
          `missing: ${missing.join(', ')}`,
      );
    }
    if (mirrorDirty.length > 0) {
      details.push(
        `ar* legacy field(s) ${mirrorDirty
          .map((k) => `${k}=${JSON.stringify(data[k])}`)
          .join(', ')} set without the rest of the contract (missing: ${missing.join(', ')})`,
      );
    }
    return { state: 'drift', detail: details.join(' | ') };
  }

  // storage-gated field: its target references Storage objects that must all
  // be verified EXACTLY present + matching before the field is writable —
  // exists, a non-null byte size that matches, a non-null custom
  // `twinArSofaGallerySha256` that matches, and (where the stat carries it) the
  // expected content type. Missing metadata blocks the migration.
  if (fieldSpec.storageObjects) {
    const failures = fieldSpec.storageObjects
      .map((o) => {
        const stat = storageVerification?.[o.objectPath];
        if (!stat || !stat.exists) return `${o.objectPath}: not staged`;
        if (stat.sizeBytes == null) {
          return `${o.objectPath}: Storage object reports no byte size`;
        }
        if (Number(stat.sizeBytes) !== o.sizeBytes) {
          return `${o.objectPath}: size ${stat.sizeBytes} != ${o.sizeBytes}`;
        }
        if (stat.sha256 == null) {
          return `${o.objectPath}: missing twinArSofaGallerySha256 custom metadata`;
        }
        if (stat.sha256 !== o.sha256) {
          return `${o.objectPath}: sha256 ${stat.sha256} != ${o.sha256}`;
        }
        if (
          o.contentType != null &&
          stat.contentType != null &&
          stat.contentType !== o.contentType
        ) {
          return `${o.objectPath}: contentType ${stat.contentType} != ${o.contentType}`;
        }
        return null;
      })
      .filter(Boolean);
    if (failures.length > 0) {
      // still classify the current value so a doc that ALREADY points at the
      // final gallery (idempotent re-run after staging) isn't wrongly blocked.
      const cur = currentValue(data, name);
      if (cur !== ABSENT && deepEqual(cur, fieldSpec.target)) {
        return { state: 'final' };
      }
      return {
        state: 'drift',
        detail: `${name}: sofa gallery objects not staged/verified — ${failures.join('; ')}`,
      };
    }
  }

  const cur = currentValue(data, name);
  const eq = (x, y) => (fieldSpec.deep ? deepEqual(x, y) : x === y);
  const matchesFinal =
    fieldSpec.target !== undefined && cur !== ABSENT && eq(cur, fieldSpec.target);
  const matchesLegacy =
    cur !== ABSENT && (fieldSpec.accept ?? []).some((a) => eq(cur, a));
  // `both`: the recognised legacy value and the final target are identical for
  // this field (e.g. the lamp title). It is coherent with an all-legacy OR an
  // all-final product and never needs a write.
  if (matchesFinal && matchesLegacy) return { state: 'both' };
  if (matchesFinal) return { state: 'final' };
  if (matchesLegacy) return { state: 'legacy' };
  return {
    state: 'drift',
    detail:
      `${name}: current value ${cur === ABSENT ? '(absent)' : JSON.stringify(cur)} ` +
      'matches neither a recognised legacy state nor the final target',
  };
}

// ── planning ────────────────────────────────────────────────────────────────

/**
 * Plan for one product. `entry` is `{ id, data, updateTime }` (or
 * `{ data: null }`). `storageVerification` maps objectPath →
 * `{ exists, sizeBytes, sha256 }` (from the read phase, sofa only).
 */
export function planProduct(entry, recastItem, storageVerification) {
  const { data } = entry;
  const base = {
    productId: recastItem.productId,
    blocked: false,
    wouldChange: false,
    reason: null,
    updateTime: entry.updateTime ?? null,
  };

  if (data == null) {
    return { ...base, status: 'missing', blocked: true, reason: 'product document does not exist' };
  }

  const diagnostics = [];

  for (const [name, allowed] of Object.entries(recastItem.validate)) {
    if (Array.isArray(allowed)) {
      if (!allowed.includes(data[name])) {
        diagnostics.push(
          `${name}: current value ${JSON.stringify(data[name])} is not one of ${allowed.map((v) => JSON.stringify(v)).join(' / ')}`,
        );
      }
    } else {
      // deep validate-only field (e.g. chair specifications)
      const cur = currentValue(data, name);
      const ok = (allowed.accept ?? []).some((a) => deepEqual(cur, a));
      if (!ok) {
        diagnostics.push(
          `${name}: current value ${cur === ABSENT ? '(absent)' : JSON.stringify(cur)} does not match the recognised value`,
        );
      }
    }
  }

  const fieldStates = {};
  for (const [name, fieldSpec] of Object.entries(recastItem.fields)) {
    const c = classifyField(data, name, fieldSpec, storageVerification);
    fieldStates[name] = c.state;
    if (c.state === 'drift') diagnostics.push(c.detail);
  }

  // Coherence: within one product every controlled field must be in the
  // recognised legacy state OR already exactly final. A field that is `both`
  // (legacy value == final target) is compatible with either. A product that
  // mixes a strictly-legacy field with a strictly-final field is a partially
  // hand-migrated document — block it for manual review rather than "finishing"
  // the migration on top of an unknown edit.
  const strictlyLegacy = Object.entries(fieldStates)
    .filter(([, s]) => s === 'legacy')
    .map(([n]) => n);
  const strictlyFinal = Object.entries(fieldStates)
    .filter(([, s]) => s === 'final')
    .map(([n]) => n);
  if (strictlyLegacy.length > 0 && strictlyFinal.length > 0) {
    diagnostics.push(
      `mixed legacy/final field states within one product — already-final: ` +
        `[${strictlyFinal.join(', ')}], still-legacy: [${strictlyLegacy.join(', ')}]. ` +
        'A coherent state is required (all controlled fields legacy, or all ' +
        'exactly final); this document needs manual review.',
    );
  }

  if (diagnostics.length > 0) {
    return {
      ...base,
      status: 'field-conflict',
      blocked: true,
      reason: diagnostics.join(' | '),
      diagnostics,
    };
  }

  // Build the write set: only the fields still in a recognised legacy state.
  // `final` and `both` are already correct and must not be re-written.
  const write = {};
  for (const [name, fieldSpec] of Object.entries(recastItem.fields)) {
    if (fieldStates[name] !== 'legacy') continue;
    if (fieldSpec.arGroup) Object.assign(write, fieldSpec.target);
    else write[name] = fieldSpec.target;
  }

  if (Object.keys(write).length === 0) {
    return { ...base, status: 'already-recast' };
  }

  return {
    ...base,
    status: 'needs-recast',
    wouldChange: true,
    updateTime: entry.updateTime ?? null,
    write,
    before: snapshotBefore(data, write),
  };
}

function snapshotBefore(data, write) {
  const before = {};
  for (const key of Object.keys(write)) {
    before[key] = Object.prototype.hasOwnProperty.call(data, key)
      ? data[key]
      : DELETE_FIELD;
  }
  return before;
}

/** Which sofa gallery objects each recast item needs verified. */
export function requiredStorageObjects() {
  const paths = new Set();
  for (const item of RECAST) {
    for (const fieldSpec of Object.values(item.fields)) {
      for (const o of fieldSpec.storageObjects ?? []) paths.add(o.objectPath);
    }
  }
  return [...paths];
}

/**
 * Reads every target document + (sofa) every required Storage object, and
 * plans each product. Performs NO writes.
 * `storageAdapter` may be null when no sofa gallery verification is possible
 * (dry-run without creds) — the sofa then blocks on `not staged`.
 */
export async function buildFullPlan(firestoreAdapter, storageAdapter) {
  const storageVerification = {};
  if (storageAdapter) {
    for (const objectPath of requiredStorageObjects()) {
      storageVerification[objectPath] = await storageAdapter.statObject(objectPath);
    }
  }
  const plans = [];
  for (const item of RECAST) {
    const entry = await firestoreAdapter.getProduct(item.productId);
    plans.push(
      planProduct({ id: item.productId, ...entry }, item, storageVerification),
    );
  }
  return { plans, storageVerification };
}

export function summarizePlans(plans) {
  const blocked = plans.filter((p) => p.blocked);
  const changing = plans.filter((p) => p.wouldChange);
  const alreadyDone = plans.filter((p) => p.status === 'already-recast');
  return {
    productsScanned: plans.length,
    documentsThatWouldChange: changing.map((p) => p.productId),
    alreadyRecast: alreadyDone.map((p) => p.productId),
    blockers: blocked.map((p) => ({
      productId: p.productId,
      status: p.status,
      reason: p.reason,
    })),
    hasBlockers: blocked.length > 0,
  };
}

// ── backup ──────────────────────────────────────────────────────────────────

function serialiseBefore(before) {
  const out = {};
  for (const [k, v] of Object.entries(before)) {
    out[k] = v === DELETE_FIELD ? { __absentBeforeMigration: true } : v;
  }
  return out;
}

export function buildBackupPayload(plans) {
  return {
    schemaVersion: BACKUP_SCHEMA_VERSION,
    createdAt: new Date().toISOString(),
    entries: plans
      .filter((p) => p.wouldChange)
      .map((p) => ({
        productId: p.productId,
        updateTimeBeforeApply: p.updateTime,
        updateTimeAfterApply: null,
        writtenKeys: Object.keys(p.write),
        finalTarget: p.write,
        before: serialiseBefore(p.before),
      })),
  };
}

/**
 * Records each committed doc's post-commit `updateTime` (the rollback
 * precondition) and DROPS any entry that was not actually written this run
 * (e.g. a product another run recast between our preflight and our
 * transaction). Only genuinely-written docs remain rollback-eligible.
 */
export function finaliseBackup(backup, postUpdateTimesById) {
  backup.entries = backup.entries.filter((e) =>
    Object.prototype.hasOwnProperty.call(postUpdateTimesById, e.productId),
  );
  for (const entry of backup.entries) {
    entry.updateTimeAfterApply = postUpdateTimesById[entry.productId];
  }
  backup.finalisedAt = new Date().toISOString();
  return backup;
}

// ── atomic commit ───────────────────────────────────────────────────────────

/**
 * The recast body of one Firestore transaction. `txAdapter` = `{ get(id) ->
 * { exists, data, updateTime }, update(id, fields) }`.
 *
 * `targetPlans` is EVERY target document's preflight plan — the ones that would
 * change AND the ones classified as already-final. Inside the transaction each
 * one is re-read and re-checked: its `updateTime` must still equal the
 * preflight value, it must not be blocked, and its recomputed status must equal
 * its preflight status. Any drift in ANY target document — a concurrent edit, a
 * field that moved, a product that raced to done — throws [MigrationAbort]
 * before a single `tx.update` is buffered, so the transaction commits nothing.
 * Only the `needs-recast` documents are written.
 */
export async function commitRecast(targetPlans, txAdapter, storageVerification) {
  const toWrite = [];
  for (const plan of targetPlans) {
    if (plan.status !== 'needs-recast' && plan.status !== 'already-recast') {
      // missing / field-conflict should have aborted the run before this point.
      throw new MigrationAbort(
        `${plan.productId}: unexpected preflight status "${plan.status}" reached the transaction`,
      );
    }
    const cur = await txAdapter.get(plan.productId);
    if (!cur.exists) {
      throw new MigrationAbort(`${plan.productId}: document no longer exists`);
    }
    if (cur.updateTime !== plan.updateTime) {
      throw new MigrationAbort(
        `${plan.productId}: concurrent modification — updateTime changed since preflight ` +
          `(was ${plan.updateTime}, now ${cur.updateTime})`,
      );
    }
    const item = recastById[plan.productId];
    const revalidated = planProduct(
      { id: plan.productId, data: cur.data, updateTime: cur.updateTime },
      item,
      storageVerification,
    );
    if (revalidated.blocked) {
      throw new MigrationAbort(`${plan.productId}: ${revalidated.reason}`);
    }
    if (revalidated.status !== plan.status) {
      throw new MigrationAbort(
        `${plan.productId}: catalogue state drifted between preflight ("${plan.status}") ` +
          `and commit ("${revalidated.status}") — aborting with zero writes`,
      );
    }
    if (revalidated.status === 'needs-recast') {
      toWrite.push({ id: plan.productId, fields: revalidated.write });
    }
  }
  for (const w of toWrite) txAdapter.update(w.id, w.fields);
  return toWrite.map((w) => w.id);
}

// ── atomic guarded rollback ─────────────────────────────────────────────────

/**
 * The exact flat Firestore field keys this migration is allowed to write for
 * one product — the non-`ar` controlled field names plus, when the product has
 * an `ar` group, its nine flat `ar*` keys. Nothing else may ever appear in a
 * rollback backup's `writtenKeys`.
 */
export function migrationControlledKeys(productId) {
  const item = recastById[productId];
  if (!item) return null;
  const keys = new Set();
  for (const [name, fieldSpec] of Object.entries(item.fields)) {
    if (fieldSpec.arGroup) {
      for (const k of Object.keys(fieldSpec.target)) keys.add(k);
    } else {
      keys.add(name);
    }
  }
  return keys;
}

function isAbsentSentinel(v) {
  return (
    v != null &&
    typeof v === 'object' &&
    !Array.isArray(v) &&
    Object.keys(v).length === 1 &&
    v.__absentBeforeMigration === true
  );
}

export function validateBackup(backup) {
  if (!backup || backup.schemaVersion !== BACKUP_SCHEMA_VERSION) {
    throw new MigrationAbort(
      `backup schemaVersion is "${backup?.schemaVersion}", expected "${BACKUP_SCHEMA_VERSION}"`,
    );
  }
  if (!Array.isArray(backup.entries) || backup.entries.length === 0) {
    throw new MigrationAbort('backup has no entries');
  }
  if (backup.entries.length > AR_PRODUCT_IDS.length) {
    throw new MigrationAbort(
      `backup has ${backup.entries.length} entries — at most ${AR_PRODUCT_IDS.length} ` +
        '(the migration-controlled products) are possible',
    );
  }

  const seenProducts = new Set();
  for (const e of backup.entries) {
    if (!e || typeof e !== 'object' || Array.isArray(e)) {
      throw new MigrationAbort('backup entry is not an object');
    }
    if (!AR_PRODUCT_IDS.includes(e.productId)) {
      throw new MigrationAbort(
        `backup references unknown product "${e.productId}" — only ` +
          `${AR_PRODUCT_IDS.join(', ')} are migration-controlled`,
      );
    }
    if (seenProducts.has(e.productId)) {
      throw new MigrationAbort(`backup lists product "${e.productId}" more than once`);
    }
    seenProducts.add(e.productId);

    if (!e.updateTimeAfterApply) {
      throw new MigrationAbort(
        `${e.productId}: backup was never finalised (no post-apply updateTime) — the migration did not complete`,
      );
    }
    if (!Array.isArray(e.writtenKeys) || e.writtenKeys.length === 0) {
      throw new MigrationAbort(`${e.productId}: backup entry has no writtenKeys`);
    }
    if (!e.finalTarget || typeof e.finalTarget !== 'object' || Array.isArray(e.finalTarget)) {
      throw new MigrationAbort(`${e.productId}: backup entry finalTarget is malformed`);
    }
    if (!e.before || typeof e.before !== 'object' || Array.isArray(e.before)) {
      throw new MigrationAbort(`${e.productId}: backup entry before-state is malformed`);
    }

    const allowed = migrationControlledKeys(e.productId);
    const writtenSet = new Set();
    for (const k of e.writtenKeys) {
      if (typeof k !== 'string') {
        throw new MigrationAbort(`${e.productId}: writtenKeys contains a non-string key`);
      }
      if (writtenSet.has(k)) {
        throw new MigrationAbort(`${e.productId}: writtenKeys lists "${k}" more than once`);
      }
      writtenSet.add(k);
      if (!allowed.has(k)) {
        throw new MigrationAbort(
          `${e.productId}: writtenKey "${k}" is not in this product's migration-controlled allowlist`,
        );
      }
    }

    const sameKeys = (obj, label) => {
      const ks = Object.keys(obj);
      if (ks.length !== writtenSet.size || ks.some((k) => !writtenSet.has(k))) {
        throw new MigrationAbort(
          `${e.productId}: ${label} keys do not exactly match writtenKeys`,
        );
      }
    };
    sameKeys(e.finalTarget, 'finalTarget');
    sameKeys(e.before, 'before-state');

    for (const k of writtenSet) {
      if (e.finalTarget[k] === undefined) {
        throw new MigrationAbort(`${e.productId}: finalTarget["${k}"] is missing`);
      }
      const b = e.before[k];
      if (b === undefined) {
        throw new MigrationAbort(`${e.productId}: before-state for "${k}" is missing`);
      }
      // a real prior value, or the EXACT absent sentinel — a partial or
      // tampered `{ __absentBeforeMigration: ... }` shape is corruption.
      if (
        b != null &&
        typeof b === 'object' &&
        !Array.isArray(b) &&
        '__absentBeforeMigration' in b &&
        !isAbsentSentinel(b)
      ) {
        throw new MigrationAbort(
          `${e.productId}: before-state for "${k}" has a malformed absent-sentinel`,
        );
      }
    }
  }
}

/**
 * The rollback body of one transaction. Restores exactly the fields this
 * migration wrote, and ONLY when the document is still in the exact
 * post-migration state (updateTime + every written field). A later or
 * unexpected edit throws [MigrationAbort] → nothing rolls back.
 */
export async function commitRollback(backup, txAdapter) {
  validateBackup(backup);
  const restores = [];
  for (const entry of backup.entries) {
    const cur = await txAdapter.get(entry.productId);
    if (!cur.exists) {
      throw new MigrationAbort(`${entry.productId}: document no longer exists`);
    }
    if (cur.updateTime !== entry.updateTimeAfterApply) {
      throw new MigrationAbort(
        `${entry.productId}: document edited since the migration ` +
          `(updateTime ${cur.updateTime} != post-migration ${entry.updateTimeAfterApply}) — refusing to roll back`,
      );
    }
    for (const key of entry.writtenKeys) {
      if (!deepEqual(cur.data[key], entry.finalTarget[key])) {
        throw new MigrationAbort(
          `${entry.productId}: field "${key}" is not in the expected post-migration state — refusing to roll back`,
        );
      }
    }
    const fields = {};
    for (const key of entry.writtenKeys) {
      const before = entry.before[key];
      fields[key] =
        before && before.__absentBeforeMigration ? DELETE_FIELD : before;
    }
    restores.push({ id: entry.productId, fields });
  }
  for (const r of restores) txAdapter.update(r.id, r.fields);
  return restores.map((r) => r.id);
}

// ── guards ──────────────────────────────────────────────────────────────────

export function assertProjectGuard(mode, confirmedProjectId) {
  if (mode !== 'apply' && mode !== 'rollback-apply') return;
  if (confirmedProjectId !== CONFIRMED_PROJECT_ID) {
    throw new Error(
      `Refusing to run live writes: --project must be exactly "${CONFIRMED_PROJECT_ID}" ` +
        `(got ${confirmedProjectId ? `"${confirmedProjectId}"` : 'nothing'}).`,
    );
  }
}

export function assertDimensionSignOff(mode, dimensionsApproved) {
  if (mode !== 'apply') return;
  if (!dimensionsApproved) {
    throw new Error(
      'BLOCKED: supervisor dimension sign-off is not recorded. The coffee ' +
        'table (Ø 90 × H 42), lamp (20 × 20 × 45) and sofa (265 × 165 × 82) ' +
        'published specs need supervisor approval before this live write. ' +
        'Re-run with --dimensions-approved once that sign-off exists.',
    );
  }
}
