import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  applyProductMigration,
  applyRollback,
  assertProjectGuard,
  buildBackupPayload,
  buildFullPlan,
  CONFIRMED_PROJECT_ID,
  DELETE_FIELD,
  planProduct,
  summarizePlans,
} from './lib.mjs';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const SEEDED_CATEGORIES = new Map([
  ['furniture', { kind: 'furniture' }],
  ['clothing', { kind: 'clothing' }],
  ['rugs', { kind: 'rugs' }],
  ['decor', { kind: 'decor' }],
  ['lighting', { kind: 'lighting' }],
]);

class FakeFirestoreAdapter {
  constructor(productsById, categoriesById = SEEDED_CATEGORIES) {
    this.productDocs = new Map(
      Object.entries(productsById).map(([id, data]) => [id, structuredClone(data)]),
    );
    this.categoryDocs = categoriesById;
    this.updateCalls = [];
  }
  async listProducts() {
    return [...this.productDocs.entries()].map(([id, data]) => ({
      id,
      data: structuredClone(data),
    }));
  }
  async listCategories() {
    return [...this.categoryDocs.entries()].map(([id, data]) => ({
      id,
      data: structuredClone(data),
    }));
  }
  async updateProduct(id, fields) {
    if (!this.productDocs.has(id)) throw new Error(`no such product ${id}`);
    const doc = this.productDocs.get(id);
    for (const [key, value] of Object.entries(fields)) {
      if (value === DELETE_FIELD) {
        delete doc[key];
      } else {
        doc[key] = value;
      }
    }
    // DELETE_FIELD is a Symbol and can't go through structuredClone, so this
    // stores the fields object as-is (fine for test assertions - it's only
    // ever read, never mutated afterward).
    this.updateCalls.push({ id, fields });
  }
}

// ---------------------------------------------------------------------------
// planProduct
// ---------------------------------------------------------------------------

describe('planProduct', () => {
  it('a legacy-shaped doc with a valid category and a matching category doc needs migration', () => {
    const plan = planProduct('p1', { category: 'furniture' }, SEEDED_CATEGORIES);
    assert.equal(plan.status, 'needs-migration');
    assert.equal(plan.wouldChange, true);
    assert.equal(plan.blocked, false);
    assert.equal(plan.targetCategoryId, 'furniture');
    assert.equal(plan.targetCategoryKind, 'furniture');
  });

  it('a doc with categoryId/categoryKind already set and consistent is already-migrated', () => {
    const plan = planProduct(
      'p1',
      { categoryId: 'furniture', categoryKind: 'furniture' },
      SEEDED_CATEGORIES,
    );
    assert.equal(plan.status, 'already-migrated');
    assert.equal(plan.wouldChange, false);
    assert.equal(plan.blocked, false);
  });

  it('a doc with a legacy category AND already-migrated fields is still recognized as already-migrated (natural Admin-edit end state)', () => {
    const plan = planProduct(
      'p1',
      { category: 'furniture', categoryId: 'furniture', categoryKind: 'furniture' },
      SEEDED_CATEGORIES,
    );
    assert.equal(plan.status, 'already-migrated');
  });

  it('an invalid/unknown legacy category value is blocked, not guessed at', () => {
    const plan = planProduct('p1', { category: 'not-a-real-category' }, SEEDED_CATEGORIES);
    assert.equal(plan.status, 'invalid-legacy-category');
    assert.equal(plan.blocked, true);
    assert.equal(plan.wouldChange, false);
    assert.match(plan.reason, /not one of the five known categories/);
  });

  it('a doc with no category field at all is blocked as invalid-legacy-category', () => {
    const plan = planProduct('p1', {}, SEEDED_CATEGORIES);
    assert.equal(plan.status, 'invalid-legacy-category');
    assert.equal(plan.blocked, true);
  });

  it('a valid legacy category whose category document does not exist is blocked', () => {
    const plan = planProduct('p1', { category: 'furniture' }, new Map());
    assert.equal(plan.status, 'category-doc-missing');
    assert.equal(plan.blocked, true);
  });

  it('a category document whose kind does not match its own id is blocked (defensive)', () => {
    const badCategories = new Map([['furniture', { kind: 'clothing' }]]);
    const plan = planProduct('p1', { category: 'furniture' }, badCategories);
    assert.equal(plan.status, 'kind-mismatch');
    assert.equal(plan.blocked, true);
  });

  it('a doc with only categoryId (no categoryKind) is a partially-migrated blocker', () => {
    const plan = planProduct('p1', { categoryId: 'furniture' }, SEEDED_CATEGORIES);
    assert.equal(plan.status, 'partially-migrated');
    assert.equal(plan.blocked, true);
    assert.match(plan.reason, /no categoryKind/);
  });

  it('a doc with only categoryKind (no categoryId) is a partially-migrated blocker', () => {
    const plan = planProduct('p1', { categoryKind: 'furniture' }, SEEDED_CATEGORIES);
    assert.equal(plan.status, 'partially-migrated');
    assert.equal(plan.blocked, true);
    assert.match(plan.reason, /no categoryId/);
  });

  it('a doc with categoryId/categoryKind present but inconsistent with the real category document is a partially-migrated blocker, not silently trusted', () => {
    const plan = planProduct(
      'p1',
      { categoryId: 'furniture', categoryKind: 'clothing' },
      SEEDED_CATEGORIES,
    );
    assert.equal(plan.status, 'partially-migrated');
    assert.equal(plan.blocked, true);
    assert.match(plan.reason, /does not match/);
  });

  it('a doc whose categoryId references a deleted category document is a partially-migrated blocker', () => {
    const plan = planProduct(
      'p1',
      { categoryId: 'ghost-category', categoryKind: 'furniture' },
      SEEDED_CATEGORIES,
    );
    assert.equal(plan.status, 'partially-migrated');
    assert.equal(plan.blocked, true);
  });

  it('captures the exact original field presence, not just values', () => {
    const plan = planProduct('p1', { category: 'furniture' }, SEEDED_CATEGORIES);
    assert.equal(plan.hadCategory, true);
    assert.equal(plan.hadCategoryId, false);
    assert.equal(plan.categoryId, null);
    assert.equal(plan.hadCategoryKind, false);
  });
});

// ---------------------------------------------------------------------------
// buildFullPlan / summarizePlans
// ---------------------------------------------------------------------------

describe('buildFullPlan / summarizePlans', () => {
  it('separates already-migrated, needs-migration, and blocked documents', async () => {
    const adapter = new FakeFirestoreAdapter({
      'already-done': { categoryId: 'furniture', categoryKind: 'furniture' },
      'needs-it': { category: 'clothing' },
      'bad-value': { category: 'nonsense' },
    });
    const plans = await buildFullPlan(adapter);
    const summary = summarizePlans(plans);

    assert.equal(summary.productsScanned, 3);
    assert.equal(summary.alreadyMigratedCount, 1);
    assert.deepEqual(summary.documentsThatWouldChange, ['needs-it']);
    assert.equal(summary.hasBlockers, true);
    assert.equal(summary.blockers.length, 1);
    assert.equal(summary.blockers[0].productId, 'bad-value');
    assert.equal(summary.blockers[0].status, 'invalid-legacy-category');
  });

  it('hasBlockers is false only when every document is clean', async () => {
    const adapter = new FakeFirestoreAdapter({
      a: { category: 'furniture' },
      b: { categoryId: 'clothing', categoryKind: 'clothing' },
    });
    const summary = summarizePlans(await buildFullPlan(adapter));
    assert.equal(summary.hasBlockers, false);
  });
});

// ---------------------------------------------------------------------------
// buildBackupPayload - exact-state capture
// ---------------------------------------------------------------------------

describe('buildBackupPayload', () => {
  it('captures exact prior presence/values only for documents that would change', async () => {
    const adapter = new FakeFirestoreAdapter({
      changing: { category: 'furniture' },
      unchanged: { categoryId: 'clothing', categoryKind: 'clothing' },
    });
    const plans = await buildFullPlan(adapter);
    const backup = buildBackupPayload(plans);

    assert.equal(backup.length, 1);
    assert.deepEqual(backup[0], {
      productId: 'changing',
      hadCategoryId: false,
      categoryId: null,
      hadCategoryKind: false,
      categoryKind: null,
    });
  });
});

// ---------------------------------------------------------------------------
// applyProductMigration - narrow writes only
// ---------------------------------------------------------------------------

describe('applyProductMigration', () => {
  it('writes only categoryId/categoryKind, never touching other fields', async () => {
    const adapter = new FakeFirestoreAdapter({
      p1: { category: 'furniture', mainImage: { path: 'x.png', source: 'asset' } },
    });
    const plan = planProduct('p1', { category: 'furniture' }, SEEDED_CATEGORIES);

    const result = await applyProductMigration(plan, adapter);

    assert.equal(result.ok, true);
    assert.equal(adapter.updateCalls.length, 1);
    assert.deepEqual(Object.keys(adapter.updateCalls[0].fields).sort(), [
      'categoryId',
      'categoryKind',
    ]);
    // mainImage survives untouched.
    assert.deepEqual(adapter.productDocs.get('p1').mainImage, {
      path: 'x.png',
      source: 'asset',
    });
    assert.equal(adapter.productDocs.get('p1').categoryId, 'furniture');
  });

  it('reports failure without throwing when the update rejects', async () => {
    const adapter = new FakeFirestoreAdapter({});
    const plan = planProduct('missing', { category: 'furniture' }, SEEDED_CATEGORIES);

    const result = await applyProductMigration(plan, adapter);

    assert.equal(result.ok, false);
    assert.match(result.error, /no such product/);
  });
});

// ---------------------------------------------------------------------------
// applyRollback - exact restoration, including field deletion
// ---------------------------------------------------------------------------

describe('applyRollback', () => {
  it('deletes categoryId/categoryKind entirely when they did not exist before', async () => {
    const adapter = new FakeFirestoreAdapter({
      p1: { category: 'furniture', categoryId: 'furniture', categoryKind: 'furniture' },
    });
    const backup = [
      {
        productId: 'p1',
        hadCategoryId: false,
        categoryId: null,
        hadCategoryKind: false,
        categoryKind: null,
      },
    ];

    const results = await applyRollback(backup, adapter);

    assert.equal(results[0].ok, true);
    const restored = adapter.productDocs.get('p1');
    assert.equal('categoryId' in restored, false);
    assert.equal('categoryKind' in restored, false);
    // The legacy field (never touched by this tool) survives.
    assert.equal(restored.category, 'furniture');
  });

  it('restores the exact prior value when the fields did exist before (e.g. undoing a re-run over a partial state)', async () => {
    const adapter = new FakeFirestoreAdapter({
      p1: { categoryId: 'new-value', categoryKind: 'new-value' },
    });
    const backup = [
      {
        productId: 'p1',
        hadCategoryId: true,
        categoryId: 'old-value',
        hadCategoryKind: true,
        categoryKind: 'old-value',
      },
    ];

    await applyRollback(backup, adapter);

    const restored = adapter.productDocs.get('p1');
    assert.equal(restored.categoryId, 'old-value');
    assert.equal(restored.categoryKind, 'old-value');
  });

  it('reports per-entry failures without aborting the whole rollback', async () => {
    const adapter = new FakeFirestoreAdapter({
      p1: { categoryId: 'furniture', categoryKind: 'furniture' },
    });
    const backup = [
      { productId: 'p1', hadCategoryId: false, categoryId: null, hadCategoryKind: false, categoryKind: null },
      { productId: 'does-not-exist', hadCategoryId: false, categoryId: null, hadCategoryKind: false, categoryKind: null },
    ];

    const results = await applyRollback(backup, adapter);

    assert.equal(results[0].ok, true);
    assert.equal(results[1].ok, false);
  });
});

// ---------------------------------------------------------------------------
// assertProjectGuard
// ---------------------------------------------------------------------------

describe('assertProjectGuard', () => {
  it('never throws for dry-run/rollback-dry-run, regardless of project', () => {
    assert.doesNotThrow(() => assertProjectGuard('dry-run', null));
    assert.doesNotThrow(() => assertProjectGuard('rollback-dry-run', 'wrong-project'));
  });

  it('throws for apply/rollback-apply unless the project is exactly CONFIRMED_PROJECT_ID', () => {
    assert.throws(() => assertProjectGuard('apply', null));
    assert.throws(() => assertProjectGuard('apply', 'some-other-project'));
    assert.throws(() => assertProjectGuard('rollback-apply', 'twin-ar-d4d75-typo'));
    assert.doesNotThrow(() => assertProjectGuard('apply', CONFIRMED_PROJECT_ID));
    assert.doesNotThrow(() => assertProjectGuard('rollback-apply', CONFIRMED_PROJECT_ID));
  });
});
