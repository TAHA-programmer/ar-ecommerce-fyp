import { beforeEach, describe, expect, it } from "vitest";

import { moderateReviewHandler } from "../src/moderateReview";
import { clearFirestore, readProductStats, readReview, seedReview, testDb } from "./helpers/emulator";

const ADMIN_UID = "admin-uid";
const AUTHOR_UID = "author-uid";
const PRODUCT_ID = "p1";
const REVIEW_ID = `${AUTHOR_UID}_${PRODUCT_ID}`;

function body(overrides: Record<string, unknown> = {}) {
  return { reviewId: REVIEW_ID, action: "hide", reason: "Violates community guidelines.", ...overrides };
}

async function call(
  data: Record<string, unknown>,
  opts: { uid?: string | undefined; role?: string | undefined } = {},
) {
  return moderateReviewHandler({
    authUid: "uid" in opts ? opts.uid : ADMIN_UID,
    authRole: "role" in opts ? opts.role : "superAdmin",
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

async function seedStats(fields: Record<string, unknown>): Promise<void> {
  await testDb.doc(`productStats/${PRODUCT_ID}`).set(fields, { merge: true });
}

beforeEach(async () => {
  await clearFirestore();
  await seedReview(REVIEW_ID, {
    userId: AUTHOR_UID,
    productId: PRODUCT_ID,
    rating: 4,
    status: "published",
  });
  await seedStats({ ratingSum: 4, ratingCount: 1, averageRating: 4, rating4Count: 1 });
});

describe("moderateReview - auth + admin authorization", () => {
  it("rejects an unauthenticated caller", async () => {
    await expectAppError(call(body(), { uid: undefined }), "UNAUTHENTICATED");
  });

  it("rejects a signed-in caller who is NOT a superAdmin", async () => {
    await expectAppError(call(body(), { role: undefined }), "ADMIN_REQUIRED");
    await expectAppError(call(body(), { role: "customer" }), "ADMIN_REQUIRED");
  });

  it("accepts the exact superAdmin claim firestore.rules' isAdmin() checks", async () => {
    const result = await call(body(), { role: "superAdmin" });
    expect(result.status).toBe("hidden");
  });
});

describe("moderateReview - validation", () => {
  it("rejects an unrecognised action", async () => {
    await expectAppError(call(body({ action: "delete" })), "INVALID_REQUEST");
  });

  it("rejects a missing reason for hide", async () => {
    await expectAppError(call({ reviewId: REVIEW_ID, action: "hide" }), "INVALID_REQUEST");
  });

  it("rejects a missing reason for restore too (v1 §0 decision 12: EVERY "
    + "action requires a reason)", async () => {
    await expectAppError(call({ reviewId: REVIEW_ID, action: "restore" }), "INVALID_REQUEST");
  });

  it("rejects a missing reason for reject", async () => {
    await expectAppError(call({ reviewId: REVIEW_ID, action: "reject" }), "INVALID_REQUEST");
  });

  it("rejects moderating a review that does not exist", async () => {
    await expectAppError(
      call(body({ reviewId: "does-not-exist" })),
      "REVIEW_NOT_FOUND",
    );
  });
});

describe("moderateReview - hide/restore/reject transitions + audit metadata", () => {
  it("hide sets status + moderatedAt/moderatedBy/moderationReason", async () => {
    await call(body({ action: "hide", reason: "Contains spam links." }));
    const review = await readReview(REVIEW_ID);
    expect(review?.status).toBe("hidden");
    expect(review?.moderatedBy).toBe(ADMIN_UID);
    expect(review?.moderationReason).toBe("Contains spam links.");
    expect(review?.moderatedAt).toBeDefined();
  });

  it("reject sets status to rejected with its own reason", async () => {
    await call(body({ action: "reject", reason: "Not a genuine review." }));
    const review = await readReview(REVIEW_ID);
    expect(review?.status).toBe("rejected");
    expect(review?.moderationReason).toBe("Not a genuine review.");
  });

  it("restore sets status back to published, with a required reason", async () => {
    await call(body({ action: "hide", reason: "Initial hide." }));
    await call(body({ action: "restore", reason: "Appeal reviewed, review is genuine." }));
    const review = await readReview(REVIEW_ID);
    expect(review?.status).toBe("published");
    expect(review?.moderationReason).toBe("Appeal reviewed, review is genuine.");
  });

  it("re-hiding an already-hidden review updates the reason without erroring", async () => {
    await call(body({ action: "hide", reason: "First reason." }));
    await call(body({ action: "hide", reason: "Updated reason." }));
    const review = await readReview(REVIEW_ID);
    expect(review?.status).toBe("hidden");
    expect(review?.moderationReason).toBe("Updated reason.");
  });
});

describe("moderateReview - transactional aggregate reversal covers every "
  + "from/to combination (v1 §0 decision 15)", () => {
  it("hide (published -> hidden) reverses the rating out of productStats", async () => {
    await call(body({ action: "hide" }));
    const stats = await readProductStats(PRODUCT_ID);
    expect(stats?.ratingCount).toBe(0);
    expect(stats?.ratingSum).toBe(0);
    expect(stats?.rating4Count).toBe(0);
  });

  it("reject (published -> rejected) also reverses it", async () => {
    await call(body({ action: "reject" }));
    const stats = await readProductStats(PRODUCT_ID);
    expect(stats?.ratingCount).toBe(0);
  });

  it("restore (hidden -> published) re-applies the rating", async () => {
    await call(body({ action: "hide" }));
    await call(body({ action: "restore" }));
    const stats = await readProductStats(PRODUCT_ID);
    expect(stats?.ratingCount).toBe(1);
    expect(stats?.ratingSum).toBe(4);
    expect(stats?.rating4Count).toBe(1);
  });

  it("hide -> reject (both non-published) does NOT touch the aggregate a "
    + "second time", async () => {
    await call(body({ action: "hide" }));
    const afterHide = await readProductStats(PRODUCT_ID);
    await call(body({ action: "reject" }));
    const afterReject = await readProductStats(PRODUCT_ID);
    expect(afterReject).toEqual(afterHide);
    expect(afterReject?.ratingCount).toBe(0);
  });

  it("restoring an ALREADY-published review is a no-op on the aggregate "
    + "(never double-applies)", async () => {
    await call(body({ action: "restore", reason: "Confirming this stays visible." }));
    const stats = await readProductStats(PRODUCT_ID);
    expect(stats?.ratingCount).toBe(1);
    expect(stats?.ratingSum).toBe(4);
  });

  it("does not affect a different product's aggregate", async () => {
    const otherReviewId = `${AUTHOR_UID}_p-other`;
    await seedReview(otherReviewId, {
      userId: AUTHOR_UID,
      productId: "p-other",
      rating: 2,
      status: "published",
    });
    await testDb
      .doc("productStats/p-other")
      .set({ ratingSum: 2, ratingCount: 1, rating2Count: 1 }, { merge: true });

    await call(body({ action: "hide" })); // hides the p1 review only

    expect((await readProductStats("p-other"))?.ratingCount).toBe(1);
  });
});
