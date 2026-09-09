import { describe, it, expect } from "vitest";

import {
  buildOrderItems,
  readSessionTotals,
  readDeliveryAddressSnapshot,
  buildOrderAndPaymentDocs,
  deliveryWindowMillis,
} from "../orderFromSession";

const addressSnapshot = {
  id: "addr-1",
  label: "Home",
  fullName: "Alice Khan",
  phoneNumber: "03001234567",
  addressLine1: "1 Test Road",
  addressLine2: null,
  city: "Karachi",
  provinceOrState: "Sindh",
  postalCode: "74000",
  isDefault: true,
};

const goodSession = {
  userId: "u1",
  items: [
    {
      productId: "p1",
      quantity: 2,
      selectedColor: "black",
      selectedSize: null,
      unitPriceRupees: 3000,
      lineTotalRupees: 6000,
      productName: "Oak Chair",
      imagePath: "products/p1/main.jpg",
      imageSource: "network",
    },
  ],
  subtotal: 6000,
  deliveryFee: 500,
  discount: 1000,
  total: 5500,
  deliveryAddressSnapshot: addressSnapshot,
};

describe("buildOrderItems", () => {
  it("maps session line items to the orders/{id}.items[] shape", () => {
    const result = buildOrderItems(goodSession.items);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.items[0]).toEqual({
      productId: "p1",
      productName: "Oak Chair",
      imagePath: "products/p1/main.jpg",
      imageSource: "network",
      quantity: 2,
      selectedSize: null,
      selectedColor: "black",
      unitPrice: 3000,
      lineTotal: 6000,
    });
  });

  it("rejects a non-list / empty / oversized / malformed items array", () => {
    expect(buildOrderItems("nope").ok).toBe(false);
    expect(buildOrderItems([]).ok).toBe(false);
    expect(buildOrderItems(Array.from({ length: 51 }, () => ({}))).ok).toBe(false);
    expect(buildOrderItems([{ productId: "p1", quantity: 0, unitPriceRupees: 1, lineTotalRupees: 1 }]).ok).toBe(false);
    expect(buildOrderItems([{ productId: "", quantity: 1, unitPriceRupees: 1, lineTotalRupees: 1 }]).ok).toBe(false);
  });
});

describe("readSessionTotals", () => {
  it("passes valid, invariant-satisfying totals", () => {
    expect(readSessionTotals(goodSession)).toEqual({
      ok: true,
      subtotal: 6000,
      deliveryFee: 500,
      discount: 1000,
      total: 5500,
    });
  });
  it("rejects a broken monetary invariant", () => {
    expect(readSessionTotals({ ...goodSession, total: 9999 }).ok).toBe(false);
    expect(readSessionTotals({ ...goodSession, discount: 999_999 }).ok).toBe(false);
    expect(readSessionTotals({ ...goodSession, subtotal: 20_000_000 }).ok).toBe(false);
  });
});

describe("readDeliveryAddressSnapshot", () => {
  it("accepts the exact 10-key snapshot", () => {
    const r = readDeliveryAddressSnapshot(goodSession);
    expect(r.ok).toBe(true);
  });
  it("rejects a missing / wrong-shaped snapshot", () => {
    expect(readDeliveryAddressSnapshot({}).ok).toBe(false);
    const { isDefault: _omit, ...missingKey } = addressSnapshot;
    expect(readDeliveryAddressSnapshot({ deliveryAddressSnapshot: missingKey }).ok).toBe(false);
  });
});

describe("buildOrderAndPaymentDocs", () => {
  it("produces rules-invariant-satisfying order + payment docs", () => {
    const TS = { __ts: true };
    const START = { __start: true };
    const END = { __end: true };
    const built = buildOrderAndPaymentDocs({
      session: goodSession,
      orderId: "ord_x",
      paymentId: "pay_x",
      serverTimestamp: TS,
      deliveryStart: START,
      deliveryEnd: END,
    });
    expect(built.ok).toBe(true);
    if (!built.ok) return;

    expect(built.orderDoc).toMatchObject({
      userId: "u1",
      paymentId: "pay_x",
      subtotal: 6000,
      deliveryFee: 500,
      discount: 1000,
      total: 5500,
      paymentMethod: "stripeCard",
      paymentStatus: "paid",
      orderStatus: "pending",
      orderDate: TS,
      estimatedDeliveryStart: START,
      estimatedDeliveryEnd: END,
    });
    expect((built.orderDoc.items as unknown[]).length).toBe(1);
    // firestore.rules invariants
    const o = built.orderDoc as Record<string, number>;
    expect(o.discount).toBeLessThanOrEqual(o.subtotal + o.deliveryFee);
    expect(o.total).toBe(o.subtotal + o.deliveryFee - o.discount);

    expect(built.paymentDoc).toEqual({
      userId: "u1",
      orderId: "ord_x",
      amount: 5500,
      method: "stripeCard",
      status: "paid",
      createdAt: TS,
    });
  });

  it("fails cleanly (no throw) on a corrupt session snapshot", () => {
    for (const bad of [
      { ...goodSession, items: "corrupt" },
      { ...goodSession, items: [] },
      { ...goodSession, total: 1 },
      { ...goodSession, userId: "" },
      { ...goodSession, deliveryAddressSnapshot: { nope: true } },
    ]) {
      const built = buildOrderAndPaymentDocs({
        session: bad,
        orderId: "ord_x",
        paymentId: "pay_x",
        serverTimestamp: {},
        deliveryStart: {},
        deliveryEnd: {},
      });
      expect(built.ok).toBe(false);
    }
  });
});

describe("deliveryWindowMillis", () => {
  it("is +7 and +14 days (matching CheckoutViewModel)", () => {
    const now = 1_000_000_000_000;
    const w = deliveryWindowMillis(now);
    expect(w.startMs).toBe(now + 7 * 24 * 60 * 60 * 1000);
    expect(w.endMs).toBe(now + 14 * 24 * 60 * 60 * 1000);
  });
});
