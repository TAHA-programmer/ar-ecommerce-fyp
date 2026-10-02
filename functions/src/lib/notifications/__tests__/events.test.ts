import { describe, expect, it } from "vitest";

import {
  classifyOrderStatusChange,
  classifyReviewChange,
  classifyStockChange,
  classifyStripeLedgerOutcome,
  timestampMillis,
} from "..";

const ts = (ms: number) => ({ toMillis: () => ms });

describe("classifyStockChange (crossing, not level)", () => {
  const stock = (n: unknown) => ({ stockQuantity: n });

  it("fires low_stock only when crossing from above the band into 1..5", () => {
    expect(classifyStockChange(stock(6), stock(5))).toBe("low_stock");
    expect(classifyStockChange(stock(10), stock(3))).toBe("low_stock");
    expect(classifyStockChange(stock(6), stock(1))).toBe("low_stock");
  });

  it("does not fire for decrements that stay inside the band", () => {
    expect(classifyStockChange(stock(5), stock(4))).toBeNull();
    expect(classifyStockChange(stock(2), stock(1))).toBeNull();
  });

  it("fires out_of_stock on any >0 -> 0, including straight from above the band", () => {
    expect(classifyStockChange(stock(1), stock(0))).toBe("out_of_stock");
    expect(classifyStockChange(stock(4), stock(0))).toBe("out_of_stock");
    expect(classifyStockChange(stock(50), stock(0))).toBe("out_of_stock");
  });

  it("never fires on restocks, no-change, or 0 -> low", () => {
    expect(classifyStockChange(stock(0), stock(3))).toBeNull();
    expect(classifyStockChange(stock(3), stock(8))).toBeNull();
    expect(classifyStockChange(stock(4), stock(4))).toBeNull();
    expect(classifyStockChange(stock(0), stock(0))).toBeNull();
  });

  it("reserve -> restore flapping at the boundary yields one low per downward crossing", () => {
    const seq = [6, 5, 6, 5, 6]; // reserve, restore, reserve, restore
    const fired = seq.slice(1).map((a, i) => classifyStockChange(stock(seq[i]), stock(a)));
    expect(fired).toEqual(["low_stock", null, "low_stock", null]);
    // the 6h cooldown ledger (dedupe.cooldownElapsed) collapses these to one push
  });

  it("tolerates missing/corrupt data without throwing", () => {
    expect(classifyStockChange(null, stock(1))).toBeNull();
    expect(classifyStockChange(stock(5), undefined)).toBeNull();
    expect(classifyStockChange({}, {})).toBeNull();
    expect(classifyStockChange(stock("abc"), stock(0))).toBeNull();
    expect(classifyStockChange(stock(6), stock(NaN))).toBeNull();
    expect(classifyStockChange(stock(2.9), stock(0))).toBe("out_of_stock");
  });

  it("honours a custom threshold", () => {
    expect(classifyStockChange(stock(11), stock(10), 10)).toBe("low_stock");
    expect(classifyStockChange(stock(6), stock(5), 10)).toBeNull();
  });
});

describe("classifyOrderStatusChange", () => {
  const o = (orderStatus: unknown) => ({ orderStatus });

  it("maps customer-facing transitions", () => {
    expect(classifyOrderStatusChange(o("pending"), o("confirmed"))).toBe("order_confirmed");
    expect(classifyOrderStatusChange(o("confirmed"), o("shipped"))).toBe("order_shipped");
    expect(classifyOrderStatusChange(o("shipped"), o("delivered"))).toBe("order_delivered");
    expect(classifyOrderStatusChange(o("pending"), o("cancelled"))).toBe("order_cancelled");
    expect(classifyOrderStatusChange(o("shipped"), o("cancelled"))).toBe("order_cancelled");
  });

  it("ignores unchanged, pending, unknown and corrupt statuses", () => {
    expect(classifyOrderStatusChange(o("shipped"), o("shipped"))).toBeNull();
    expect(classifyOrderStatusChange(o("confirmed"), o("pending"))).toBeNull();
    expect(classifyOrderStatusChange(o("pending"), o("teleported"))).toBeNull();
    expect(classifyOrderStatusChange(o("pending"), o(undefined))).toBeNull();
    expect(classifyOrderStatusChange(o("pending"), o(42))).toBeNull();
    expect(classifyOrderStatusChange(null, o("confirmed"))).toBeNull();
  });
});

describe("classifyReviewChange", () => {
  const base = {
    status: "published",
    flaggedForReview: false,
    moderatedBy: null,
    moderatedAt: null,
  };

  it("flags once on false -> true only", () => {
    expect(classifyReviewChange(base, { ...base, flaggedForReview: true })).toEqual([
      { kind: "flagged" },
    ]);
    const already = { ...base, flaggedForReview: true };
    expect(classifyReviewChange(already, { ...already, reportCount: 9 })).toEqual([]);
  });

  it("notifies hidden/rejected/restored only for an admin action", () => {
    const hidden = classifyReviewChange(base, {
      ...base,
      status: "hidden",
      moderatedBy: "admin1",
      moderatedAt: ts(1_700_000_000_000),
    });
    expect(hidden).toEqual([
      { kind: "moderated", type: "review_hidden", moderatedAtMs: 1_700_000_000_000 },
    ]);

    const rejected = classifyReviewChange(base, {
      ...base,
      status: "rejected",
      moderatedBy: "admin1",
      moderatedAt: ts(1_700_000_000_001),
    });
    expect(rejected[0]).toMatchObject({ type: "review_rejected" });

    const hiddenBefore = { ...base, status: "hidden", moderatedBy: "a", moderatedAt: ts(1) };
    const restored = classifyReviewChange(hiddenBefore, {
      ...hiddenBefore,
      status: "published",
      moderatedAt: ts(2),
    });
    expect(restored).toEqual([{ kind: "moderated", type: "review_restored", moderatedAtMs: 2 }]);
  });

  it("GOTCHA: an author edit/re-publish (moderatedBy reset to null) is never moderation", () => {
    const moderated = {
      ...base,
      status: "hidden",
      moderatedBy: "admin1",
      moderatedAt: ts(5),
    };
    // submitReview resets moderatedAt/moderatedBy to null and re-publishes
    expect(
      classifyReviewChange(moderated, {
        ...base,
        status: "published",
        moderatedBy: null,
        moderatedAt: null,
      }),
    ).toEqual([]);
  });

  it("ignores re-moderation that leaves status unchanged, or a non-advancing timestamp", () => {
    const hidden = { ...base, status: "hidden", moderatedBy: "a", moderatedAt: ts(10) };
    expect(classifyReviewChange(hidden, { ...hidden, moderatedAt: ts(11) })).toEqual([]);
    expect(
      classifyReviewChange(base, { ...base, status: "hidden", moderatedBy: "a", moderatedAt: ts(10) })
        .length,
    ).toBe(1);
    expect(
      classifyReviewChange(
        { ...base, moderatedBy: "a", moderatedAt: ts(10) },
        { ...base, status: "hidden", moderatedBy: "a", moderatedAt: ts(10) },
      ),
    ).toEqual([]);
  });

  it("can emit flagged and moderated together and tolerates corrupt data", () => {
    const both = classifyReviewChange(base, {
      ...base,
      flaggedForReview: true,
      status: "hidden",
      moderatedBy: "a",
      moderatedAt: ts(7),
    });
    expect(both.map((e) => e.kind)).toEqual(["flagged", "moderated"]);
    expect(classifyReviewChange(null, base)).toEqual([]);
    expect(
      classifyReviewChange(base, { ...base, status: "hidden", moderatedBy: "", moderatedAt: ts(1) }),
    ).toEqual([]);
    expect(
      classifyReviewChange(base, { ...base, status: "mystery", moderatedBy: "a", moderatedAt: ts(1) }),
    ).toEqual([]);
  });
});

describe("classifyStripeLedgerOutcome", () => {
  it("maps the refund and anomaly outcomes only", () => {
    expect(classifyStripeLedgerOutcome("refunded_reservation_lost:expired")).toEqual({
      kind: "refund",
      sessionStatus: "expired",
    });
    expect(classifyStripeLedgerOutcome("refunded_reservation_lost:failed")).toEqual({
      kind: "refund",
      sessionStatus: "failed",
    });
    expect(classifyStripeLedgerOutcome("inconsistent_order_payment")).toEqual({ kind: "anomaly" });
  });

  it("ignores every other ledger outcome", () => {
    for (const o of [
      "finalized",
      "released",
      "already_finalized",
      "duplicate_event",
      "session_corrupt:status_empty",
      "deferred_pi_could_still_succeed",
      "",
    ]) {
      expect(classifyStripeLedgerOutcome(o)).toBeNull();
    }
    expect(classifyStripeLedgerOutcome(undefined)).toBeNull();
    expect(classifyStripeLedgerOutcome(5)).toBeNull();
  });
});

describe("timestampMillis", () => {
  it("reads Timestamp-likes, numbers and seconds/nanos objects; null otherwise", () => {
    expect(timestampMillis(ts(123))).toBe(123);
    expect(timestampMillis(456)).toBe(456);
    expect(timestampMillis({ seconds: 2, nanoseconds: 500_000_000 })).toBe(2500);
    expect(timestampMillis({ _seconds: 3, _nanoseconds: 0 })).toBe(3000);
    expect(timestampMillis(null)).toBeNull();
    expect(timestampMillis("x")).toBeNull();
    expect(timestampMillis({})).toBeNull();
  });
});
