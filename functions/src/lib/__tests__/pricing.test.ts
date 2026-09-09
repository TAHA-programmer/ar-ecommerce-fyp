import { describe, it, expect } from "vitest";

import {
  computeOrderTotals,
  DELIVERY_FEE_RUPEES,
  NOMINAL_DISCOUNT_RUPEES,
  MAX_MONETARY_RUPEES,
} from "../pricing";

describe("computeOrderTotals", () => {
  it("mirrors CheckoutViewModel for a normal cart: sum(unitPrice * qty) + flat delivery - flat discount", () => {
    const totals = computeOrderTotals([
      { productId: "a", quantity: 2, unitPriceRupees: 3000 },
      { productId: "b", quantity: 1, unitPriceRupees: 1500 },
    ]);
    expect(totals.subtotal).toBe(7500);
    expect(totals.deliveryFee).toBe(DELIVERY_FEE_RUPEES);
    expect(totals.discount).toBe(NOMINAL_DISCOUNT_RUPEES); // clamp is a no-op here
    expect(totals.total).toBe(7500 + 500 - 1000);
  });

  it("clamps the discount for a small cart so total is never negative AND the invariant holds exactly", () => {
    const totals = computeOrderTotals([
      { productId: "a", quantity: 1, unitPriceRupees: 300 },
    ]);
    // subtotal 300 + delivery 500 = 800; discount clamps to 800; total = 0.
    expect(totals.subtotal).toBe(300);
    expect(totals.deliveryFee).toBe(500);
    expect(totals.discount).toBe(800);
    expect(totals.total).toBe(0);
    // The two firestore.rules invariants that used to be violated:
    expect(totals.discount).toBeLessThanOrEqual(totals.subtotal + totals.deliveryFee);
    expect(totals.total).toBe(totals.subtotal + totals.deliveryFee - totals.discount);
  });

  it("every result satisfies the firestore.rules monetary invariants", () => {
    for (const price of [1, 100, 499, 500, 501, 1000, 25_000, 9_999_000]) {
      const t = computeOrderTotals([{ productId: "p", quantity: 1, unitPriceRupees: price }]);
      expect(t.subtotal).toBeGreaterThanOrEqual(0);
      expect(t.total).toBeGreaterThanOrEqual(0);
      expect(t.discount).toBeLessThanOrEqual(t.subtotal + t.deliveryFee);
      expect(t.total).toBe(t.subtotal + t.deliveryFee - t.discount);
      for (const v of Object.values(t)) {
        expect(Number.isInteger(v)).toBe(true);
        expect(v).toBeLessThanOrEqual(MAX_MONETARY_RUPEES);
      }
    }
  });

  it("rejects an empty cart", () => {
    expect(() => computeOrderTotals([])).toThrow();
  });

  it("rejects non-positive / non-integer quantities and negative / non-integer prices", () => {
    expect(() =>
      computeOrderTotals([{ productId: "a", quantity: 0, unitPriceRupees: 100 }]),
    ).toThrow();
    expect(() =>
      computeOrderTotals([{ productId: "a", quantity: 1.5, unitPriceRupees: 100 }]),
    ).toThrow();
    expect(() =>
      computeOrderTotals([{ productId: "a", quantity: 1, unitPriceRupees: -5 }]),
    ).toThrow();
    expect(() =>
      computeOrderTotals([{ productId: "a", quantity: 1, unitPriceRupees: 10.5 }]),
    ).toThrow();
  });

  it("rejects a subtotal past the shared 10,000,000-rupee ceiling", () => {
    expect(() =>
      computeOrderTotals([
        { productId: "a", quantity: 1, unitPriceRupees: MAX_MONETARY_RUPEES + 1 },
      ]),
    ).toThrow();
  });
});
