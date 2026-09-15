import { describe, expect, it } from "vitest";

import { reviewDocId, reviewReportDocId } from "../model";

describe("reviewDocId", () => {
  it("is deterministic per user+product - the one-review-per-user-per-product "
    + "enforcement mechanism", () => {
    expect(reviewDocId("u1", "p1")).toBe(reviewDocId("u1", "p1"));
    expect(reviewDocId("u1", "p1")).toBe("u1_p1");
  });

  it("differs for a different user or product", () => {
    expect(reviewDocId("u1", "p1")).not.toBe(reviewDocId("u2", "p1"));
    expect(reviewDocId("u1", "p1")).not.toBe(reviewDocId("u1", "p2"));
  });
});

describe("reviewReportDocId", () => {
  it("is deterministic per reporter+review - the one-report-per-user-per-review "
    + "enforcement mechanism", () => {
    expect(reviewReportDocId("r1", "rev1")).toBe(reviewReportDocId("r1", "rev1"));
    expect(reviewReportDocId("r1", "rev1")).toBe("r1_rev1");
  });

  it("differs for a different reporter or review", () => {
    expect(reviewReportDocId("r1", "rev1")).not.toBe(reviewReportDocId("r2", "rev1"));
    expect(reviewReportDocId("r1", "rev1")).not.toBe(reviewReportDocId("r1", "rev2"));
  });
});
