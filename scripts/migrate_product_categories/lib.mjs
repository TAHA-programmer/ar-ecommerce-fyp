// TWin AR — Phase 8.8b product category reference backfill, core logic.
//
// Pure/injectable functions only — no direct firebase-admin usage here, so
// this module can be unit-tested with fake Firestore adapters. The CLI
// entry point (migrate_product_categories.mjs) wires this up to the real
// Admin SDK.
//
// Scope: backfills `categoryId`/`categoryKind` onto live `products/{id}`
// documents that still only carry the legacy `category` field (or nothing
// at all), by matching the legacy enum-name value against a real
// `categories/{categoryId}` document (categoryId === the legacy enum name
// for the five originally-seeded categories). Never touches
// `mainImage`/`galleryMedia`/any other product field — every write here is
// a narrow `.update({ categoryId, categoryKind })` only, never `.set()`.
//
// Unlike scripts/migrate_product_images/ (which applies per-product,
// independently skipping/reporting blocked ones), this tool is
// all-or-nothing across the WHOLE run: if validation finds ANY invalid,
// missing, mismatched, or partially-migrated document, the apply is
// aborted completely — zero writes are made — and every blocker is
// reported, so a partial/inconsistent live dataset is never produced by a
// single run. Re-run after fixing the flagged documents (by hand, or via a
// follow-up decision) once the report is clean.

export const CONFIRMED_PROJECT_ID = 'twin-ar-d4d75';

export const KNOWN_LEGACY_CATEGORIES = [
  'furniture',
  'clothing',
  'rugs',
  'decor',
  'lighting',
];

/** Sentinel meaning "this field did not exist before - delete it on rollback",
 * translated by the CLI's real Firestore adapter to
 * `admin.firestore.FieldValue.delete()`. Exported so both the pure logic
 * here and the CLI's rollback wiring share one definition. */
export const DELETE_FIELD = Symbol('DELETE_FIELD');

/**
 * Builds a plan for one product document. Every branch is mutually
 * exclusive and reported with an exact `status`, so the CLI's summary can
 * distinguish "already done" (nothing to do, not an error) from every kind
 * of blocker (never silently coerced into "needs migration").
 */
export function planProduct(productId, data, categoryDocsById) {
  const hadCategory = Object.prototype.hasOwnProperty.call(data, 'category');
  const category = hadCategory ? data.category : null;
  const hadCategoryId = Object.prototype.hasOwnProperty.call(
    data,
    'categoryId',
  );
  const categoryId = hadCategoryId ? data.categoryId : null;
  const hadCategoryKind = Object.prototype.hasOwnProperty.call(
    data,
    'categoryKind',
  );
  const categoryKind = hadCategoryKind ? data.categoryKind : null;

  const base = {
    productId,
    hadCategory,
    category,
    hadCategoryId,
    categoryId,
    hadCategoryKind,
    categoryKind,
    blocked: false,
    wouldChange: false,
    targetCategoryId: null,
    targetCategoryKind: null,
    reason: null,
  };

  // Already fully migrated: both new fields present and internally/
  // externally consistent - a legitimate end state whether it got there via
  // this script on a prior run OR via a normal Admin edit (which naturally
  // drops the legacy field through updateProduct's full .set() - see
  // ProductModel/product_firestore_mapper.dart's Phase 8.8b doc comments).
  if (hadCategoryId && hadCategoryKind) {
    const categoryDoc = categoryDocsById.get(categoryId);
    const consistent =
      categoryDoc != null && categoryDoc.kind === categoryKind;
    if (consistent) {
      return { ...base, status: 'already-migrated' };
    }
    return {
      ...base,
      status: 'partially-migrated',
      blocked: true,
      reason: categoryDoc == null
        ? `categoryId "${categoryId}" does not reference an existing category document`
        : `categoryKind "${categoryKind}" does not match category "${categoryId}"'s real kind "${categoryDoc.kind}"`,
    };
  }

  // Exactly one of the two new fields present - an inconsistent half-
  // migrated state that must never be silently "fixed" by guessing the
  // other field's value.
  if (hadCategoryId !== hadCategoryKind) {
    return {
      ...base,
      status: 'partially-migrated',
      blocked: true,
      reason: hadCategoryId
        ? 'has categoryId but no categoryKind'
        : 'has categoryKind but no categoryId',
    };
  }

  // Neither new field present - candidate for migration from the legacy
  // `category` value.
  if (!hadCategory || !KNOWN_LEGACY_CATEGORIES.includes(category)) {
    return {
      ...base,
      status: 'invalid-legacy-category',
      blocked: true,
      reason: hadCategory
        ? `legacy "category" value "${category}" is not one of the five known categories`
        : 'no "category" field present, and no categoryId/categoryKind either',
    };
  }

  const categoryDoc = categoryDocsById.get(category);
  if (categoryDoc == null) {
    return {
      ...base,
      status: 'category-doc-missing',
      blocked: true,
      reason: `no categories/${category} document exists to migrate this product's legacy "category" value against`,
    };
  }
  if (categoryDoc.kind !== category) {
    return {
      ...base,
      status: 'kind-mismatch',
      blocked: true,
      reason: `categories/${category}'s kind ("${categoryDoc.kind}") does not match its own document id`,
    };
  }

  return {
    ...base,
    status: 'needs-migration',
    wouldChange: true,
    targetCategoryId: category,
    targetCategoryKind: category,
  };
}

/**
 * Reads every product and every category doc, and builds a plan per
 * product. Performs no writes - safe for both dry-run reporting and as the
 * read phase before an apply run.
 */
export async function buildFullPlan(firestoreAdapter) {
  const [products, categories] = await Promise.all([
    firestoreAdapter.listProducts(),
    firestoreAdapter.listCategories(),
  ]);
  const categoryDocsById = new Map(
    categories.map(({ id, data }) => [id, data]),
  );
  return products.map(({ id, data }) => planProduct(id, data, categoryDocsById));
}

export function summarizePlans(plans) {
  const byStatus = {};
  for (const plan of plans) {
    (byStatus[plan.status] ??= []).push(plan);
  }
  const blocked = plans.filter((p) => p.blocked);
  const changing = plans.filter((p) => p.wouldChange);
  const alreadyMigrated = byStatus['already-migrated'] ?? [];

  return {
    productsScanned: plans.length,
    alreadyMigratedCount: alreadyMigrated.length,
    documentsThatWouldChange: changing.map((p) => p.productId),
    blockers: blocked.map((p) => ({
      productId: p.productId,
      status: p.status,
      reason: p.reason,
    })),
    hasBlockers: blocked.length > 0,
  };
}

/** Exact prior-state backup, written before any apply-mode write. */
export function buildBackupPayload(plans) {
  return plans
    .filter((p) => p.wouldChange)
    .map((p) => ({
      productId: p.productId,
      hadCategoryId: p.hadCategoryId,
      categoryId: p.categoryId,
      hadCategoryKind: p.hadCategoryKind,
      categoryKind: p.categoryKind,
    }));
}

/**
 * Applies one already-validated plan via a narrow field-only update -
 * never touches mainImage/galleryMedia or any other product field.
 */
export async function applyProductMigration(plan, firestoreAdapter) {
  try {
    await firestoreAdapter.updateProduct(plan.productId, {
      categoryId: plan.targetCategoryId,
      categoryKind: plan.targetCategoryKind,
    });
    return { productId: plan.productId, ok: true };
  } catch (err) {
    return {
      productId: plan.productId,
      ok: false,
      error: err?.message ?? String(err),
    };
  }
}

/**
 * Restores every entry in a backup payload to its EXACT original state:
 * a field that didn't exist before this script touched it is deleted
 * (via [DELETE_FIELD], translated by the CLI to
 * `admin.firestore.FieldValue.delete()`), never left as a stray value.
 */
export async function applyRollback(backupPayload, firestoreAdapter) {
  const results = [];
  for (const entry of backupPayload) {
    try {
      await firestoreAdapter.updateProduct(entry.productId, {
        categoryId: entry.hadCategoryId ? entry.categoryId : DELETE_FIELD,
        categoryKind: entry.hadCategoryKind
          ? entry.categoryKind
          : DELETE_FIELD,
      });
      results.push({ productId: entry.productId, ok: true });
    } catch (err) {
      results.push({
        productId: entry.productId,
        ok: false,
        error: err?.message ?? String(err),
      });
    }
  }
  return results;
}

/**
 * Pure guard used by the CLI before it ever constructs a real Admin SDK
 * client for a live write - identical contract to
 * scripts/migrate_product_images/lib.mjs's assertProjectGuard.
 */
export function assertProjectGuard(mode, confirmedProjectId) {
  if (mode !== 'apply' && mode !== 'rollback-apply') return;
  if (confirmedProjectId !== CONFIRMED_PROJECT_ID) {
    throw new Error(
      `Refusing to run live writes: --project must be exactly "${CONFIRMED_PROJECT_ID}" ` +
        `(got ${confirmedProjectId ? `"${confirmedProjectId}"` : 'nothing'}). ` +
        'This guard exists so a copy-pasted command can never silently write to the wrong project.',
    );
  }
}
