import { beforeEach, describe, expect, it } from "vitest";

import { reportReviewHandler } from "../src/reportReview";
import { REVIEW_REPORT_FLAG_THRESHOLD } from "../src/config";
import { clearFirestore, readReview, seedReview, testDb } from "./helpers/emulator";

const AUTHOR_UID = "author-uid";
const REVIEWER_UID = "reviewer-uid";
const PRODUCT_ID = "p1";
const REVIEW_ID = `${AUTHOR_UID}_${PRODUCT_ID}`;

function body(overrides: Record<string, unknown> = {}) {
  return { reviewId: REVIEW_ID, reason: "spam", ...overrides };
}

async function call(data: Record<string, unknown>, opts: { uid?: string | undefined } = {}) {
  return reportReviewHandler({
    authUid: "uid" in opts ? opts.uid : REVIEWER_UID,
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

async function readReportCount(): Promise<{ reportCount: number; flaggedForReview: boolean }> {
  const review = await readReview(REVIEW_ID);
  return {
    reportCount: (review?.reportCount as number) ?? -1,
    flaggedForReview: Boolean(review?.flaggedForReview),
  };
}

beforeEach(async () => {
  await clearFirestore();
  await seedReview(REVIEW_ID, {
    userId: AUTHOR_UID,
    productId: PRODUCT_ID,
    rating: 3,
    status: "published",
    reportCount: 0,
    flaggedForReview: false,
  });
});

describe("reportReview - auth + validation", () => {
  it("rejects an unauthenticated caller", async () => {
    await expectAppError(call(body(), { uid: undefined }), "UNAUTHENTICATED");
  });

  it("rejects an unrecognised reason", async () => {
    await expectAppError(call(body({ reason: "bogus" })), "INVALID_REQUEST");
  });

  it("rejects reporting a review that does not exist", async () => {
    await expectAppError(
      call(body({ reviewId: "does-not-exist" })),
      "REVIEW_NOT_FOUND",
    );
  });
});

describe("reportReview - cannot report your own review", () => {
  it("rejects the review's own author reporting it", async () => {
    await expectAppError(call(body(), { uid: AUTHOR_UID }), "CANNOT_REPORT_OWN_REVIEW");
    expect((await readReportCount()).reportCount).toBe(0);
  });
});

describe("reportReview - one report per user per review (v1 §0 decision 10)", () => {
  it("a first report increments reportCount", async () => {
    const result = await call(body());
    expect(result).toEqual({ reported: true });
    expect((await readReportCount()).reportCount).toBe(1);
  });

  it("a repeat report from the SAME user is a harmless no-op - never a "
    + "duplicate count", async () => {
    await call(body());
    const second = await call(body({ reason: "offensive" }));
    expect(second).toEqual({ reported: false });
    expect((await readReportCount()).reportCount).toBe(1);
  });

  it("different users reporting the same review each count once", async () => {
    await call(body(), { uid: "reporter-1" });
    await call(body(), { uid: "reporter-2" });
    await call(body(), { uid: "reporter-3" });
    expect((await readReportCount()).reportCount).toBe(3);
  });
});

describe("reportReview - threshold flagging, never auto-hide (v1 §0 "
  + "decision 11)", () => {
  it("flaggedForReview stays false below the threshold", async () => {
    for (let i = 0; i < REVIEW_REPORT_FLAG_THRESHOLD - 1; i++) {
      await call(body(), { uid: `reporter-${i}` });
    }
    const state = await readReportCount();
    expect(state.reportCount).toBe(REVIEW_REPORT_FLAG_THRESHOLD - 1);
    expect(state.flaggedForReview).toBe(false);
  });

  it("flaggedForReview becomes true exactly at the threshold, and the "
    + "review stays published (never auto-hidden)", async () => {
    for (let i = 0; i < REVIEW_REPORT_FLAG_THRESHOLD; i++) {
      await call(body(), { uid: `reporter-${i}` });
    }
    const state = await readReportCount();
    expect(state.reportCount).toBe(REVIEW_REPORT_FLAG_THRESHOLD);
    expect(state.flaggedForReview).toBe(true);

    const review = await readReview(REVIEW_ID);
    expect(review?.status).toBe("published");
  });

  it("stays flagged past the threshold (monotonic)", async () => {
    for (let i = 0; i < REVIEW_REPORT_FLAG_THRESHOLD + 2; i++) {
      await call(body(), { uid: `reporter-${i}` });
    }
    expect((await readReportCount()).flaggedForReview).toBe(true);
  });
});

describe("reportReview - reports are Admin-only readable (rule intent "
  + "documented, seeded here for the report record itself)", () => {
  it("writes the report doc with the reporter's id and chosen reason", async () => {
    await call(body({ reason: "fake", note: "This looks copy-pasted." }));
    const reportSnap = await testDb.doc(`reviewReports/${REVIEWER_UID}_${REVIEW_ID}`).get();
    expect(reportSnap.exists).toBe(true);
    expect(reportSnap.data()?.reporterId).toBe(REVIEWER_UID);
    expect(reportSnap.data()?.reason).toBe("fake");
    expect(reportSnap.data()?.note).toBe("This looks copy-pasted.");
  });
});
