import { beforeEach, describe, expect, it } from "vitest";

import { FALLBACK_REVIEWER_DISPLAY_NAME } from "../src/lib/reviews/authorDisplayName";
import { submitReviewHandler } from "../src/submitReview";
import {
  clearFirestore,
  readProductStats,
  readReview,
  seedOrder,
  seedReview,
  seedUserProfile,
  Timestamp,
} from "./helpers/emulator";

const UID = "alice-uid";
const OTHER_UID = "bob-uid";
const PRODUCT_ID = "p1";
const NOW = 1_700_000_000_000; // fixed instant for deterministic edit-window math

function body(overrides: Record<string, unknown> = {}) {
  return {
    productId: PRODUCT_ID,
    rating: 5,
    title: "Great",
    body: "Exactly as described, fast delivery, very happy with it.",
    ...overrides,
  };
}

async function call(
  data: Record<string, unknown>,
  opts: { uid?: string | undefined; now?: number } = {},
) {
  return submitReviewHandler({
    authUid: "uid" in opts ? opts.uid : UID,
    data,
    now: () => opts.now ?? NOW,
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

describe("submitReview - auth + validation", () => {
  it("rejects an unauthenticated caller before touching Firestore", async () => {
    await expectAppError(call(body(), { uid: undefined }), "UNAUTHENTICATED");
    expect(await readReview(`${UID}_${PRODUCT_ID}`)).toBeUndefined();
  });

  it("rejects an invalid rating", async () => {
    await expectAppError(call(body({ rating: 0 })), "INVALID_REQUEST");
  });

  it("rejects a too-short body", async () => {
    await expectAppError(call(body({ body: "short" })), "INVALID_REQUEST");
  });
});

describe("submitReview - eligibility (v1 §0 decision 1)", () => {
  it("rejects a caller with no delivered order for this product", async () => {
    await expectAppError(call(body()), "NOT_ELIGIBLE");
    expect(await readReview(`${UID}_${PRODUCT_ID}`)).toBeUndefined();
  });

  it("rejects a caller whose order for this product is NOT delivered yet", async () => {
    await seedOrder("order-1", {
      userId: UID,
      orderStatus: "shipped",
      items: [{ productId: PRODUCT_ID, quantity: 1 }],
    });
    await expectAppError(call(body()), "NOT_ELIGIBLE");
  });

  it("rejects a caller whose delivered order is for a DIFFERENT product", async () => {
    await seedOrder("order-1", {
      userId: UID,
      orderStatus: "delivered",
      items: [{ productId: "some-other-product", quantity: 1 }],
    });
    await expectAppError(call(body()), "NOT_ELIGIBLE");
  });

  it("rejects a caller reviewing with SOMEONE ELSE's delivered order", async () => {
    await seedOrder("order-1", {
      userId: OTHER_UID,
      orderStatus: "delivered",
      items: [{ productId: PRODUCT_ID, quantity: 1 }],
    });
    await expectAppError(call(body()), "NOT_ELIGIBLE");
  });

  it("accepts a caller with a genuinely delivered order containing the product", async () => {
    await seedOrder("order-1", {
      userId: UID,
      orderStatus: "delivered",
      items: [{ productId: PRODUCT_ID, quantity: 1 }],
    });
    const result = await call(body());
    expect(result).toEqual({ reviewId: `${UID}_${PRODUCT_ID}`, edited: false });

    const saved = await readReview(`${UID}_${PRODUCT_ID}`);
    expect(saved?.rating).toBe(5);
    expect(saved?.title).toBe("Great");
    expect(saved?.userId).toBe(UID);
    expect(saved?.productId).toBe(PRODUCT_ID);
    expect(saved?.orderId).toBe("order-1");
    expect(saved?.status).toBe("published");
    expect(saved?.reportCount).toBe(0);
    expect(saved?.flaggedForReview).toBe(false);
    expect(saved?.editedAt).toBeNull();
    expect(saved?.createdAt).toBeInstanceOf(Timestamp);
  });
});

describe("submitReview - one review per user per product, even after repeat "
  + "purchases (v1 §0 decisions 2, 6)", () => {
  beforeEach(async () => {
    await seedOrder("order-1", {
      userId: UID,
      orderStatus: "delivered",
      items: [{ productId: PRODUCT_ID, quantity: 1 }],
    });
  });

  it("a second submission for the same product EDITS the same document", async () => {
    await call(body({ rating: 3, body: "Initial thoughts after unboxing it today." }));

    // Simulate a second delivered order for the same product.
    await seedOrder("order-2", {
      userId: UID,
      orderStatus: "delivered",
      items: [{ productId: PRODUCT_ID, quantity: 1 }],
    });
    const result = await call(
      body({ rating: 5, body: "Updated after a second purchase, even better." }),
      { now: NOW + 1000 },
    );
    expect(result.edited).toBe(true);
    expect(result.reviewId).toBe(`${UID}_${PRODUCT_ID}`);

    const saved = await readReview(`${UID}_${PRODUCT_ID}`);
    expect(saved?.rating).toBe(5);
    expect(saved?.orderId).toBe(
      "order-1",
    ); // the ORIGINAL qualifying order is preserved
    expect(saved?.editedAt).toBeInstanceOf(Timestamp);

    const stats = await readProductStats(PRODUCT_ID);
    expect(stats?.ratingCount).toBe(1); // never double-counted
    expect(stats?.ratingSum).toBe(5);
  });

  it("an edit within the 30-day window succeeds", async () => {
    await call(body({ rating: 2 }));
    const result = await call(body({ rating: 4 }), {
      now: NOW + 29 * 24 * 60 * 60 * 1000,
    });
    expect(result.edited).toBe(true);
    expect((await readReview(`${UID}_${PRODUCT_ID}`))?.rating).toBe(4);
  });

  it("an edit exactly at the 30-day boundary still succeeds", async () => {
    await call(body({ rating: 2 }));
    const result = await call(body({ rating: 4 }), {
      now: NOW + 30 * 24 * 60 * 60 * 1000,
    });
    expect(result.edited).toBe(true);
  });

  it("an edit one millisecond past the 30-day window is refused", async () => {
    await call(body({ rating: 2 }));
    await expectAppError(
      call(body({ rating: 4 }), { now: NOW + 30 * 24 * 60 * 60 * 1000 + 1 }),
      "EDIT_WINDOW_EXPIRED",
    );
    expect((await readReview(`${UID}_${PRODUCT_ID}`))?.rating).toBe(2);
  });
});

describe("submitReview - transactional rating aggregate (v1 §0 decision 15)", () => {
  beforeEach(async () => {
    await seedOrder("order-1", {
      userId: UID,
      orderStatus: "delivered",
      items: [{ productId: PRODUCT_ID, quantity: 1 }],
    });
  });

  it("a create adds exactly once to productStats", async () => {
    await call(body({ rating: 4 }));
    const stats = await readProductStats(PRODUCT_ID);
    expect(stats?.ratingCount).toBe(1);
    expect(stats?.ratingSum).toBe(4);
    expect(stats?.rating4Count).toBe(1);
    expect(stats?.averageRating).toBe(4);
  });

  it("an edit reverses the OLD rating before applying the new one", async () => {
    await call(body({ rating: 2 }));
    await call(body({ rating: 5 }), { now: NOW + 1000 });
    const stats = await readProductStats(PRODUCT_ID);
    expect(stats?.ratingCount).toBe(1);
    expect(stats?.ratingSum).toBe(5);
    expect(stats?.rating2Count).toBe(0);
    expect(stats?.rating5Count).toBe(1);
  });

  it("editing a review that was left HIDDEN by moderation does not "
    + "double-subtract (forward-compatible with Stage 3)", async () => {
    // A hidden review's rating was never counted toward the aggregate in
    // the first place - seed one directly, with productStats still at zero.
    await seedReview(`${UID}_${PRODUCT_ID}`, {
      userId: UID,
      productId: PRODUCT_ID,
      orderId: "order-1",
      rating: 1,
      status: "hidden",
      createdAt: Timestamp.fromMillis(NOW),
    });

    await call(body({ rating: 5 }), { now: NOW + 1000 });

    const stats = await readProductStats(PRODUCT_ID);
    expect(stats?.ratingCount).toBe(1); // the +1 for the new rating only
    expect(stats?.ratingSum).toBe(5); // never -1 for the never-counted hidden rating
  });

  it("does not affect a different product's aggregate", async () => {
    await seedOrder("order-other", {
      userId: UID,
      orderStatus: "delivered",
      items: [{ productId: "p-other", quantity: 1 }],
    });
    await call(body({ productId: PRODUCT_ID, rating: 5 }));
    await call(body({ productId: "p-other", rating: 1 }));

    expect((await readProductStats(PRODUCT_ID))?.ratingSum).toBe(5);
    expect((await readProductStats("p-other"))?.ratingSum).toBe(1);
  });
});

describe("submitReview - authorDisplayName snapshot (v1 §0 decision 13 / §6)", () => {
  beforeEach(async () => {
    await seedOrder("order-1", {
      userId: UID,
      orderStatus: "delivered",
      items: [{ productId: PRODUCT_ID, quantity: 1 }],
    });
  });

  it("resolves and masks the caller's OWN profile displayName onto the "
    + "review, never the raw name", async () => {
    await seedUserProfile(UID, { displayName: "Alice Khan" });
    await call(body());

    const saved = await readReview(`${UID}_${PRODUCT_ID}`);
    expect(saved?.authorDisplayName).toBe("Alice K.");
  });

  it("falls back to the safe default when the caller has no profile "
    + "document at all", async () => {
    await call(body());
    const saved = await readReview(`${UID}_${PRODUCT_ID}`);
    expect(saved?.authorDisplayName).toBe(FALLBACK_REVIEWER_DISPLAY_NAME);
  });

  it("falls back to the safe default when the profile's displayName is "
    + "blank", async () => {
    await seedUserProfile(UID, { displayName: "" });
    await call(body());
    const saved = await readReview(`${UID}_${PRODUCT_ID}`);
    expect(saved?.authorDisplayName).toBe(FALLBACK_REVIEWER_DISPLAY_NAME);
  });

  it("re-resolves on an edit, reflecting a since-changed profile name", async () => {
    await seedUserProfile(UID, { displayName: "Ayesha Raza" });
    await call(body({ rating: 3 }));
    expect((await readReview(`${UID}_${PRODUCT_ID}`))?.authorDisplayName).toBe(
      "Ayesha R.",
    );

    await seedUserProfile(UID, { displayName: "Ayesha Malik" });
    await call(body({ rating: 4 }), { now: NOW + 1000 });
    expect((await readReview(`${UID}_${PRODUCT_ID}`))?.authorDisplayName).toBe(
      "Ayesha M.",
    );
  });

  it("never stores the caller's email or any other raw profile field on "
    + "the review", async () => {
    await seedUserProfile(UID, {
      displayName: "Alice Khan",
      email: "alice.private@example.com",
      phone: "03001234567",
    });
    await call(body());

    const saved = await readReview(`${UID}_${PRODUCT_ID}`);
    expect(JSON.stringify(saved)).not.toContain("alice.private@example.com");
    expect(JSON.stringify(saved)).not.toContain("03001234567");
  });
});
