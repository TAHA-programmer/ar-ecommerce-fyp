import { describe, expect, it } from "vitest";

import {
  parseDeleteReviewRequest,
  parseModerateReviewRequest,
  parseReportReviewRequest,
  parseSubmitReviewRequest,
} from "../validation";

function expectInvalid(fn: () => unknown) {
  expect(fn).toThrow();
  try {
    fn();
  } catch (err) {
    const details = (err as { details?: Record<string, unknown> }).details ?? {};
    expect(details.appCode).toBe("INVALID_REQUEST");
  }
}

describe("parseSubmitReviewRequest", () => {
  const valid = () => ({
    productId: "p1",
    rating: 5,
    title: "Great",
    body: "Exactly as described and arrived quickly, very happy.",
  });

  it("accepts a fully valid request", () => {
    const parsed = parseSubmitReviewRequest(valid());
    expect(parsed).toEqual({
      productId: "p1",
      rating: 5,
      title: "Great",
      body: "Exactly as described and arrived quickly, very happy.",
    });
  });

  it("accepts a request with no title (optional)", () => {
    const data = valid();
    delete (data as Record<string, unknown>).title;
    const parsed = parseSubmitReviewRequest(data);
    expect(parsed.title).toBeNull();
  });

  it("rejects a non-object body", () => {
    expectInvalid(() => parseSubmitReviewRequest("not an object"));
    expectInvalid(() => parseSubmitReviewRequest(null));
    expectInvalid(() => parseSubmitReviewRequest([1, 2, 3]));
  });

  it("rejects a missing/empty productId", () => {
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), productId: "" }));
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), productId: undefined }));
  });

  it("rejects a productId that looks like a path traversal", () => {
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), productId: "a/b" }));
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), productId: ".." }));
  });

  it("rejects a non-integer or out-of-range rating", () => {
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), rating: 3.5 }));
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), rating: 0 }));
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), rating: 6 }));
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), rating: "5" }));
  });

  it("rejects a title over 80 characters", () => {
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), title: "a".repeat(81) }));
  });

  it("accepts a title of exactly 80 characters", () => {
    const parsed = parseSubmitReviewRequest({ ...valid(), title: "a".repeat(80) });
    expect(parsed.title?.length).toBe(80);
  });

  it("trims whitespace-only title to null", () => {
    const parsed = parseSubmitReviewRequest({ ...valid(), title: "   " });
    expect(parsed.title).toBeNull();
  });

  it("rejects a body shorter than 10 characters", () => {
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), body: "short" }));
  });

  it("rejects a body longer than 1000 characters", () => {
    expectInvalid(() => parseSubmitReviewRequest({ ...valid(), body: "a".repeat(1001) }));
  });

  it("accepts a body of exactly 10 and exactly 1000 characters", () => {
    expect(parseSubmitReviewRequest({ ...valid(), body: "a".repeat(10) }).body.length).toBe(10);
    expect(parseSubmitReviewRequest({ ...valid(), body: "a".repeat(1000) }).body.length).toBe(
      1000,
    );
  });

  it("trims the body", () => {
    const parsed = parseSubmitReviewRequest({ ...valid(), body: "  padded body text here  " });
    expect(parsed.body).toBe("padded body text here");
  });
});

describe("parseDeleteReviewRequest", () => {
  it("accepts a valid productId", () => {
    expect(parseDeleteReviewRequest({ productId: "p1" })).toEqual({ productId: "p1" });
  });

  it("rejects a missing productId", () => {
    expectInvalid(() => parseDeleteReviewRequest({}));
  });
});

describe("parseReportReviewRequest", () => {
  it("accepts a valid report with a note", () => {
    const parsed = parseReportReviewRequest({
      reviewId: "u1_p1",
      reason: "spam",
      note: "Looks like a copy-pasted ad.",
    });
    expect(parsed).toEqual({
      reviewId: "u1_p1",
      reason: "spam",
      note: "Looks like a copy-pasted ad.",
    });
  });

  it("accepts a report with no note (optional)", () => {
    const parsed = parseReportReviewRequest({ reviewId: "u1_p1", reason: "other" });
    expect(parsed.note).toBeNull();
  });

  it("rejects a missing reviewId", () => {
    expectInvalid(() => parseReportReviewRequest({ reason: "spam" }));
  });

  it("rejects an unrecognised reason", () => {
    expectInvalid(() => parseReportReviewRequest({ reviewId: "u1_p1", reason: "not-a-reason" }));
  });

  it("accepts every documented reason value", () => {
    for (const reason of ["spam", "offensive", "fake", "other"]) {
      expect(parseReportReviewRequest({ reviewId: "u1_p1", reason }).reason).toBe(reason);
    }
  });

  it("rejects a note over the max length", () => {
    expectInvalid(() =>
      parseReportReviewRequest({ reviewId: "u1_p1", reason: "spam", note: "a".repeat(501) }),
    );
  });

  it("trims a whitespace-only note to null", () => {
    const parsed = parseReportReviewRequest({ reviewId: "u1_p1", reason: "spam", note: "   " });
    expect(parsed.note).toBeNull();
  });
});

describe("parseModerateReviewRequest", () => {
  it("accepts a valid hide/restore/reject request", () => {
    for (const action of ["hide", "restore", "reject"] as const) {
      const parsed = parseModerateReviewRequest({
        reviewId: "u1_p1",
        action,
        reason: "Violates community guidelines.",
      });
      expect(parsed).toEqual({
        reviewId: "u1_p1",
        action,
        reason: "Violates community guidelines.",
      });
    }
  });

  it("rejects an unrecognised action", () => {
    expectInvalid(() =>
      parseModerateReviewRequest({ reviewId: "u1_p1", action: "delete", reason: "x" }),
    );
  });

  it("requires a reason for EVERY action, including restore (v1 §0 "
    + "decision 12)", () => {
    expectInvalid(() => parseModerateReviewRequest({ reviewId: "u1_p1", action: "hide" }));
    expectInvalid(() => parseModerateReviewRequest({ reviewId: "u1_p1", action: "restore" }));
    expectInvalid(() => parseModerateReviewRequest({ reviewId: "u1_p1", action: "reject" }));
  });

  it("rejects a whitespace-only reason", () => {
    expectInvalid(() =>
      parseModerateReviewRequest({ reviewId: "u1_p1", action: "hide", reason: "   " }),
    );
  });

  it("rejects a reason over the max length", () => {
    expectInvalid(() =>
      parseModerateReviewRequest({ reviewId: "u1_p1", action: "hide", reason: "a".repeat(501) }),
    );
  });
});
