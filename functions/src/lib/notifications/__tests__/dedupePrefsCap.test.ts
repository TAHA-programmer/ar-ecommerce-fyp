import { describe, expect, it } from "vitest";

import {
  DedupeKeyError,
  RECIPIENT_PUSH_CAP,
  RECIPIENT_PUSH_WINDOW_MS,
  adminKeys,
  categoryAllowedForRole,
  cooldownElapsed,
  customerOrderKey,
  evaluateRecipientCap,
  isPushEnabledByPrefs,
  prefKeyFor,
  refundKey,
  reviewModerationKey,
} from "..";

describe("dedupe keys", () => {
  it("are deterministic and one-per-status for orders", () => {
    expect(customerOrderKey("order_confirmed", "ord_abc")).toBe("order_confirmed_ord_abc");
    expect(customerOrderKey("order_confirmed", "ord_abc")).toBe(
      customerOrderKey("order_confirmed", "ord_abc"),
    );
    expect(customerOrderKey("order_shipped", "ord_abc")).not.toBe(
      customerOrderKey("order_confirmed", "ord_abc"),
    );
  });

  it("refund and moderation keys", () => {
    expect(refundKey("pi_123")).toBe("refund_pi_123");
    expect(reviewModerationKey("review_hidden", "u_p", 1700000000000)).toBe(
      "review_hidden_u_p_1700000000000",
    );
    expect(reviewModerationKey("review_hidden", "u_p", 1)).not.toBe(
      reviewModerationKey("review_hidden", "u_p", 2),
    );
  });

  it("admin keys address the ledger", () => {
    expect(adminKeys.newOrder("ord_1")).toBe("admin_order_ord_1");
    expect(adminKeys.lowStock("p1")).toBe("admin_lowstock_p1");
    expect(adminKeys.outOfStock("p1")).toBe("admin_oos_p1");
    expect(adminKeys.reviewFlagged("u_p")).toBe("admin_flag_u_p");
    expect(adminKeys.anomaly("evt_9")).toBe("admin_anomaly_evt_9");
  });

  it("reject ids that could escape a document path or blow the size limit", () => {
    for (const bad of ["", "a/b", "..", "a b", "x".repeat(201), "é"]) {
      if (bad === "..") continue; // dots alone are charset-legal; '/' is the path hazard
      expect(() => customerOrderKey("order_shipped", bad)).toThrow(DedupeKeyError);
    }
    expect(() => reviewModerationKey("review_hidden", "u_p", 0)).toThrow(DedupeKeyError);
    expect(() => reviewModerationKey("review_hidden", "u_p", 1.5)).toThrow(DedupeKeyError);
  });
});

describe("cooldownElapsed", () => {
  const H6 = 6 * 60 * 60 * 1000;
  it("allows when never sent, blocks inside the window, allows after", () => {
    expect(cooldownElapsed(null, 1000, H6)).toBe(true);
    expect(cooldownElapsed(undefined, 1000, H6)).toBe(true);
    expect(cooldownElapsed(0, H6 - 1, H6)).toBe(false);
    expect(cooldownElapsed(0, H6, H6)).toBe(true);
  });
  it("treats a future lastSent (clock skew) as still cooling down", () => {
    expect(cooldownElapsed(10_000, 1000, H6)).toBe(false);
  });
});

describe("push preferences (D7)", () => {
  it("defaults ON for a missing doc, missing key, or non-boolean value", () => {
    expect(isPushEnabledByPrefs("orders", null)).toBe(true);
    expect(isPushEnabledByPrefs("orders", undefined)).toBe(true);
    expect(isPushEnabledByPrefs("orders", {})).toBe(true);
    expect(isPushEnabledByPrefs("orders", { pushOrders: "no" })).toBe(true);
    expect(isPushEnabledByPrefs("orders", { pushOrders: 0 })).toBe(true);
    expect(isPushEnabledByPrefs("orders", { pushOrders: null })).toBe(true);
  });

  it("only an explicit false turns a category off - including order updates", () => {
    expect(isPushEnabledByPrefs("orders", { pushOrders: false })).toBe(false);
    expect(isPushEnabledByPrefs("reviews", { pushReviews: false })).toBe(false);
    expect(isPushEnabledByPrefs("adminStock", { pushAdminStock: false })).toBe(false);
    expect(isPushEnabledByPrefs("orders", { pushOrders: true })).toBe(true);
  });

  it("categories are independent", () => {
    const p = { pushOrders: false };
    expect(isPushEnabledByPrefs("reviews", p)).toBe(true);
    expect(isPushEnabledByPrefs("adminOrders", p)).toBe(true);
  });

  it("maps each category to its documented pref key", () => {
    expect(prefKeyFor("orders")).toBe("pushOrders");
    expect(prefKeyFor("reviews")).toBe("pushReviews");
    expect(prefKeyFor("adminOrders")).toBe("pushAdminOrders");
    expect(prefKeyFor("adminStock")).toBe("pushAdminStock");
    expect(prefKeyFor("adminModeration")).toBe("pushAdminModeration");
    expect(prefKeyFor("adminPayments")).toBe("pushAdminPayments");
  });

  it("admin categories are honoured only for a verified superAdmin", () => {
    expect(categoryAllowedForRole("adminOrders", "customer")).toBe(false);
    expect(categoryAllowedForRole("adminPayments", "customer")).toBe(false);
    expect(categoryAllowedForRole("adminOrders", "superAdmin")).toBe(true);
    expect(categoryAllowedForRole("orders", "customer")).toBe(true);
    expect(categoryAllowedForRole("orders", "superAdmin")).toBe(false);
  });
});

describe("evaluateRecipientCap", () => {
  it("allows up to the cap inside the window then drops without recording", () => {
    let history: number[] = [];
    const now = 1_000_000;
    for (let i = 0; i < RECIPIENT_PUSH_CAP; i++) {
      const r = evaluateRecipientCap(history, now + i);
      expect(r.allowed).toBe(true);
      history = r.history;
    }
    const blocked = evaluateRecipientCap(history, now + 100);
    expect(blocked.allowed).toBe(false);
    expect(blocked.history.length).toBe(RECIPIENT_PUSH_CAP); // drop not recorded
  });

  it("recovers once old entries age out of the window", () => {
    const start = 5_000_000;
    const history = Array.from({ length: RECIPIENT_PUSH_CAP }, (_, i) => start + i);
    expect(evaluateRecipientCap(history, start + 10).allowed).toBe(false);
    const later = start + RECIPIENT_PUSH_WINDOW_MS + RECIPIENT_PUSH_CAP;
    const r = evaluateRecipientCap(history, later);
    expect(r.allowed).toBe(true);
    expect(r.history).toEqual([later]);
  });

  it("ignores corrupt / future timestamps", () => {
    const r = evaluateRecipientCap([NaN, 9e15, 100], 1000, 2, 5000);
    expect(r.allowed).toBe(true);
    expect(r.history).toEqual([100, 1000]);
  });
});
