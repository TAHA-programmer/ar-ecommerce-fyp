import { beforeEach, describe, expect, it } from "vitest";

import { deleteReviewHandler } from "../src/deleteReview";
import {
  clearFirestore,
  readProductStats,
  readReview,
  seedReview,
  testDb,
  Timestamp,
} from "./helpers/emulator";

const UID = "alice-uid";
const PRODUCT_ID = "p1";

function body(overrides: Record<string, unknown> = {}) {
  return { productId: PRODUCT_ID, ...overrides };
}

async function call(data: Record<string, unknown>, opts: { uid?: string | undefined } = {}) {
  return deleteReviewHandler({
    authUid: "uid" in opts ? opts.uid : UID,
    data,
  });
}

async function expectAppError(promise: Promise<unknown>, appCode: string) {
  try {
    await promise;
  } catch (err) {
    const details = (err as { details?: Record<string, unknown> }).details ?? {};
    expect(
      details.appCode,
      `expected appCode ${appCode}, got error: ${JSON.stringify(err)}`,
    ).toBe(appCode);
    return err as { code?: string; details?: Record<string, unknown> };
  }
  throw new Error(`expected the call to reject with appCode ${appCode}, but it resolved`);
}

beforeEach(async () => {
  await clearFirestore();
});

describe("deleteReview - auth", () => {
  it("rejects an unauthenticated caller", async () => {
    await expectAppError(call(body(), { uid: undefined }), "UNAUTHENTICATED");
  });

  it("rejects an invalid request", async () => {
    await expectAppError(call({}), "INVALID_REQUEST");
  });
});

describe("deleteReview - no time limit (v1 §0 decision 7)", () => {
  it("deletes a review created long ago without any edit-window check", async () => {
    const longAgo = Timestamp.fromMillis(Date.now() - 400 * 24 * 60 * 60 * 1000);
    await seedReview(`${UID}_${PRODUCT_ID}`, {
      userId: UID,
      productId: PRODUCT_ID,
      rating: 5,
      status: "published",
      createdAt: longAgo,
    });
    await call(body());
    expect(await readReview(`${UID}_${PRODUCT_ID}`)).toBeUndefined();
  });
});

describe("deleteReview - ownership by construction", () => {
  it("cannot address another user's review - only the caller's own "
    + "deterministic doc is ever touched", async () => {
    const otherUid = "bob-uid";
    await seedReview(`${otherUid}_${PRODUCT_ID}`, {
      userId: otherUid,
      productId: PRODUCT_ID,
      rating: 5,
      status: "published",
    });

    await call(body(), { uid: UID }); // Alice has no review - harmless no-op

    // Bob's review is completely untouched.
    expect(await readReview(`${otherUid}_${PRODUCT_ID}`)).toBeDefined();
  });
});

describe("deleteReview - no-op for a nonexistent review", () => {
  it("succeeds silently when the caller has no review for this product", async () => {
    await expect(call(body())).resolves.toBeUndefined();
  });
});

describe("deleteReview - transactional rating aggregate reversal (v1 §0 "
  + "decision 15)", () => {
  it("reverses a PUBLISHED review's contribution entirely", async () => {
    await seedReview(`${UID}_${PRODUCT_ID}`, {
      userId: UID,
      productId: PRODUCT_ID,
      rating: 4,
      status: "published",
    });
    // Seed the aggregate as if `submitReview` had created it.
    await seedProductStatsForTest(PRODUCT_ID, {
      ratingSum: 4,
      ratingCount: 1,
      averageRating: 4,
      rating4Count: 1,
    });

    await call(body());

    const stats = await readProductStats(PRODUCT_ID);
    expect(stats?.ratingCount).toBe(0);
    expect(stats?.ratingSum).toBe(0);
    expect(stats?.rating4Count).toBe(0);
  });

  it("does NOT touch the aggregate when the review was already HIDDEN "
    + "(it was never counted - Stage 3 forward-compatibility)", async () => {
    await seedReview(`${UID}_${PRODUCT_ID}`, {
      userId: UID,
      productId: PRODUCT_ID,
      rating: 1,
      status: "hidden",
    });
    // A different, genuinely-published review already contributes to the
    // aggregate - deleting the hidden one must leave this untouched.
    await seedProductStatsForTest(PRODUCT_ID, {
      ratingSum: 5,
      ratingCount: 1,
      averageRating: 5,
      rating5Count: 1,
    });

    await call(body());

    const stats = await readProductStats(PRODUCT_ID);
    expect(stats?.ratingSum).toBe(5);
    expect(stats?.ratingCount).toBe(1);
  });

  it("does not affect a different product's aggregate", async () => {
    await seedReview(`${UID}_p1`, { userId: UID, productId: "p1", rating: 5, status: "published" });
    await seedProductStatsForTest("p1", { ratingSum: 5, ratingCount: 1, rating5Count: 1 });
    await seedProductStatsForTest("p-other", { ratingSum: 3, ratingCount: 1, rating3Count: 1 });

    await call({ productId: "p1" });

    expect((await readProductStats("p1"))?.ratingCount).toBe(0);
    expect((await readProductStats("p-other"))?.ratingCount).toBe(1);
  });
});

// Local helper - seeds ONLY the productStats fields a test needs, without
// pulling in the full submitReview flow (which is exercised separately).
async function seedProductStatsForTest(
  productId: string,
  fields: Record<string, unknown>,
): Promise<void> {
  await testDb.doc(`productStats/${productId}`).set(fields, { merge: true });
}
