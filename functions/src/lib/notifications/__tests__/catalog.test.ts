import { describe, expect, it } from "vitest";

import {
  ADMIN_NOTIFICATION_TYPES,
  CATALOG,
  CUSTOMER_NOTIFICATION_TYPES,
  NotificationCatalogError,
  renderNotification,
  sanitizeFragment,
  shortOrderId,
  type NotificationParams,
  type NotificationType,
} from "..";

const ORDER_ID = "ord_0123456789abcdef0123456789abcdef01234567";
const PARAMS: NotificationParams = {
  orderId: ORDER_ID,
  reviewId: "uid1_prod1",
  productId: "prod1",
  productTitle: "Luna Accent Chair",
  stockQuantity: 3,
};

const ALL: NotificationType[] = [...CUSTOMER_NOTIFICATION_TYPES, ...ADMIN_NOTIFICATION_TYPES];

describe("catalogue shape", () => {
  it("has an entry for every type", () => {
    for (const t of ALL) expect(CATALOG[t]).toBeDefined();
    expect(Object.keys(CATALOG).sort()).toEqual([...ALL].sort());
  });

  it("customer types always have an inbox row; admin types never do", () => {
    for (const t of CUSTOMER_NOTIFICATION_TYPES) {
      expect(CATALOG[t].audience).toBe("customer");
      expect(CATALOG[t].inbox).toBe(true);
    }
    for (const t of ADMIN_NOTIFICATION_TYPES) {
      expect(CATALOG[t].audience).toBe("admin");
      expect(CATALOG[t].inbox).toBe(false);
    }
  });

  it("inbox-only types never push (order_placed, review_restored)", () => {
    expect(CATALOG.order_placed.pushes).toBe(false);
    expect(CATALOG.review_restored.pushes).toBe(false);
    for (const t of ALL) {
      if (t !== "order_placed" && t !== "review_restored") expect(CATALOG[t].pushes).toBe(true);
    }
  });

  it("D6: review moderation pushes use the low-priority account channel", () => {
    for (const t of ["review_hidden", "review_rejected", "review_restored"] as const) {
      expect(CATALOG[t].channelId).toBe("account");
      expect(CATALOG[t].androidPriority).toBe("normal");
      expect(CATALOG[t].category).toBe("reviews");
    }
  });

  it("D7: every order push (incl. refund) is gated by the single 'orders' category", () => {
    for (const t of [
      "order_confirmed",
      "order_shipped",
      "order_delivered",
      "order_cancelled",
      "payment_refunded",
    ] as const) {
      expect(CATALOG[t].category).toBe("orders");
      expect(CATALOG[t].channelId).toBe("orders");
      expect(CATALOG[t].androidPriority).toBe("high");
    }
  });

  it("channels match the plan §4.5 table", () => {
    expect(CATALOG.admin_new_order.channelId).toBe("admin_ops");
    expect(CATALOG.admin_payment_issue.channelId).toBe("admin_ops");
    expect(CATALOG.admin_low_stock.channelId).toBe("admin_stock");
    expect(CATALOG.admin_out_of_stock.channelId).toBe("admin_stock");
    expect(CATALOG.admin_review_flagged.channelId).toBe("admin_stock");
  });

  it("admin deep-link routes match plan §4.3", () => {
    expect(CATALOG.admin_new_order.route).toBe("adminOrderDetail");
    expect(CATALOG.admin_low_stock.route).toBe("adminInventory");
    expect(CATALOG.admin_out_of_stock.route).toBe("adminInventory");
    expect(CATALOG.admin_review_flagged.route).toBe("adminReviews");
    expect(CATALOG.admin_payment_issue.route).toBe("adminNotifications");
  });
});

describe("renderNotification copy", () => {
  it("renders every type with non-empty title/body and a tag", () => {
    for (const t of ALL) {
      const r = renderNotification(t, PARAMS);
      expect(r.title.length).toBeGreaterThan(0);
      expect(r.body.length).toBeGreaterThan(0);
      expect(r.tag.length).toBeGreaterThan(0);
      expect(r.type).toBe(t);
    }
  });

  it("is lock-screen safe: no raw 44-char order id, no money, no reporter/reason words", () => {
    for (const t of ALL) {
      const text = `${renderNotification(t, PARAMS).title} ${renderNotification(t, PARAMS).body}`;
      expect(text).not.toContain(ORDER_ID);
      expect(text).not.toMatch(/Rs\.?\s?\d|PKR|\$\d/i);
      expect(text).not.toMatch(/reporter|reported by|reason:/i);
    }
  });

  it("order copy uses the short id mirrored from the Flutter formatter", () => {
    expect(renderNotification("order_shipped", PARAMS).body).toContain("#01234567");
  });

  it("cancellation never promises a refund", () => {
    const body = renderNotification("order_cancelled", PARAMS).body.toLowerCase();
    expect(body).not.toContain("refund");
    expect(body).toContain("cancelled");
  });

  it("payment_refunded states a refund was issued, with no amount", () => {
    const r = renderNotification("payment_refunded");
    expect(r.body.toLowerCase()).toContain("refund");
    expect(r.entityId).toBeNull();
    expect(r.route).toBe("orders");
  });

  it("moderation copy is generic (no reason, no reporter)", () => {
    for (const t of ["review_hidden", "review_rejected"] as const) {
      const r = renderNotification(t, PARAMS);
      expect(`${r.title} ${r.body}`).not.toMatch(/report|spam|offensive|fake/i);
    }
  });

  it("low stock includes bounded product title and quantity", () => {
    const r = renderNotification("admin_low_stock", PARAMS);
    expect(r.body).toBe("Luna Accent Chair: 3 left.");
    expect(r.tag).toBe("admin_stock_prod1");
  });

  it("order statuses share one tag per order so the tray entry is replaced", () => {
    const tags = (["order_confirmed", "order_shipped", "order_delivered"] as const).map(
      (t) => renderNotification(t, PARAMS).tag,
    );
    expect(new Set(tags).size).toBe(1);
    expect(tags[0]).toBe(ORDER_ID);
  });

  it("throws a typed error when a required entity id is missing", () => {
    expect(() => renderNotification("order_shipped", {})).toThrow(NotificationCatalogError);
    expect(() => renderNotification("review_hidden", {})).toThrow(NotificationCatalogError);
    expect(() => renderNotification("admin_low_stock", {})).toThrow(NotificationCatalogError);
  });
});

describe("shortOrderId / sanitizeFragment", () => {
  it("shortens webhook ids and bounds anything else", () => {
    expect(shortOrderId(ORDER_ID)).toBe("#01234567");
    expect(shortOrderId("#TW00000001")).toBe("#TW00000001");
    expect(shortOrderId("legacyorderid-very-long-value").length).toBeLessThanOrEqual(12);
  });

  it("strips control chars/whitespace runs and truncates long titles", () => {
    expect(sanitizeFragment("  A\n\tB   C\u0000", "x")).toBe("A B C");
    expect(sanitizeFragment("", "fallback")).toBe("fallback");
    expect(sanitizeFragment(undefined, "fallback")).toBe("fallback");
    const long = sanitizeFragment("x".repeat(200), "f");
    expect(long.length).toBe(60);
    expect(long.endsWith("…")).toBe(true);
  });
});
