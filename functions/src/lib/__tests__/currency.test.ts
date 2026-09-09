import { describe, it, expect } from "vitest";

import {
  toStripeMinorUnits,
  STRIPE_ZERO_DECIMAL_CURRENCIES,
  MAX_STRIPE_MINOR_UNITS,
} from "../currency";

describe("toStripeMinorUnits", () => {
  it("multiplies whole rupees by 100 for PKR (a two-decimal currency)", () => {
    expect(toStripeMinorUnits(500, "pkr")).toBe(50000);
    expect(toStripeMinorUnits(1, "PKR")).toBe(100);
    expect(toStripeMinorUnits(0, "pkr")).toBe(0);
    expect(toStripeMinorUnits(4500, "pkr")).toBe(450000);
  });

  it("does not scale zero-decimal currencies", () => {
    expect(toStripeMinorUnits(500, "jpy")).toBe(500);
    expect(toStripeMinorUnits(1200, "KRW")).toBe(1200);
  });

  it("PKR is not on the zero-decimal list", () => {
    expect(STRIPE_ZERO_DECIMAL_CURRENCIES.has("pkr")).toBe(false);
  });

  it("rounds an exact half-unit input to an integer", () => {
    // 2.5 is exactly representable; 2.5 * 100 = 250 exactly.
    expect(toStripeMinorUnits(2.5, "pkr")).toBe(250);
  });

  it("rejects negative, non-finite, and non-number amounts", () => {
    expect(() => toStripeMinorUnits(-1, "pkr")).toThrow();
    expect(() => toStripeMinorUnits(Number.NaN, "pkr")).toThrow();
    expect(() => toStripeMinorUnits(Number.POSITIVE_INFINITY, "pkr")).toThrow();
    // @ts-expect-error - guarding the runtime path against a bad caller
    expect(() => toStripeMinorUnits("500", "pkr")).toThrow();
  });

  it("rejects an empty currency code", () => {
    expect(() => toStripeMinorUnits(100, "")).toThrow();
    expect(() => toStripeMinorUnits(100, "   ")).toThrow();
  });

  it("rejects an amount past the shared monetary ceiling", () => {
    const overCeilingRupees = MAX_STRIPE_MINOR_UNITS / 100 + 1;
    expect(() => toStripeMinorUnits(overCeilingRupees, "pkr")).toThrow();
  });
});
