import { describe, it, expect } from "vitest";

import {
  parseCreatePaymentIntentRequest,
  MAX_LINE_ITEMS,
  MAX_QUANTITY_PER_LINE,
} from "../validation";

function validBody(overrides: Record<string, unknown> = {}) {
  return {
    addressId: "addr_1",
    idempotencyKey: "idem-key-abcdef",
    items: [{ productId: "p1", quantity: 2, selectedColor: "black", selectedSize: null }],
    ...overrides,
  };
}

describe("parseCreatePaymentIntentRequest", () => {
  it("accepts a well-formed request and normalises variants", () => {
    const parsed = parseCreatePaymentIntentRequest(
      validBody({
        items: [
          { productId: "p1", quantity: 1, selectedColor: "", selectedSize: undefined },
          { productId: "p2", quantity: 3 },
        ],
      }),
    );
    expect(parsed.addressId).toBe("addr_1");
    expect(parsed.idempotencyKey).toBe("idem-key-abcdef");
    expect(parsed.items[0]).toEqual({
      productId: "p1",
      quantity: 1,
      selectedColor: null,
      selectedSize: null,
    });
    expect(parsed.items[1].selectedColor).toBeNull();
  });

  it("rejects a non-object body", () => {
    for (const bad of [null, undefined, 42, "x", []]) {
      expect(() => parseCreatePaymentIntentRequest(bad)).toThrow();
    }
  });

  it("rejects a missing / malformed addressId", () => {
    expect(() => parseCreatePaymentIntentRequest(validBody({ addressId: undefined }))).toThrow();
    expect(() => parseCreatePaymentIntentRequest(validBody({ addressId: "" }))).toThrow();
    expect(() => parseCreatePaymentIntentRequest(validBody({ addressId: 5 }))).toThrow();
    expect(() =>
      parseCreatePaymentIntentRequest(validBody({ addressId: "a/b" })),
    ).toThrow();
    expect(() =>
      parseCreatePaymentIntentRequest(validBody({ addressId: "x".repeat(201) })),
    ).toThrow();
  });

  it("rejects a missing / too-short idempotencyKey", () => {
    expect(() =>
      parseCreatePaymentIntentRequest(validBody({ idempotencyKey: undefined })),
    ).toThrow();
    expect(() =>
      parseCreatePaymentIntentRequest(validBody({ idempotencyKey: "short" })),
    ).toThrow();
    expect(() =>
      parseCreatePaymentIntentRequest(validBody({ idempotencyKey: 123 })),
    ).toThrow();
  });

  it("rejects an empty / oversized / non-array items list", () => {
    expect(() => parseCreatePaymentIntentRequest(validBody({ items: [] }))).toThrow();
    expect(() => parseCreatePaymentIntentRequest(validBody({ items: "nope" }))).toThrow();
    const tooMany = Array.from({ length: MAX_LINE_ITEMS + 1 }, (_, i) => ({
      productId: `p${i}`,
      quantity: 1,
    }));
    expect(() => parseCreatePaymentIntentRequest(validBody({ items: tooMany }))).toThrow();
  });

  it("rejects a bad line item (productId, quantity bounds, slash, non-integer)", () => {
    const cases: unknown[] = [
      { productId: "", quantity: 1 },
      { productId: "p1", quantity: 0 },
      { productId: "p1", quantity: -1 },
      { productId: "p1", quantity: 1.5 },
      { productId: "p1", quantity: MAX_QUANTITY_PER_LINE + 1 },
      { productId: "p1", quantity: "2" },
      { productId: "p/1", quantity: 1 },
      { productId: "p1" },
      "not-an-object",
    ];
    for (const item of cases) {
      expect(() => parseCreatePaymentIntentRequest(validBody({ items: [item] }))).toThrow();
    }
  });

  it("never trusts a client-sent price / total / userId / stock (they are simply ignored)", () => {
    const parsed = parseCreatePaymentIntentRequest(
      validBody({
        subtotal: 1,
        total: 1,
        userId: "someone-else",
        items: [
          {
            productId: "p1",
            quantity: 1,
            unitPriceRupees: 1,
            priceAmount: 1,
            stockQuantity: 999,
          },
        ],
      }),
    );
    expect(parsed).not.toHaveProperty("subtotal");
    expect(parsed).not.toHaveProperty("userId");
    expect(Object.keys(parsed.items[0]).sort()).toEqual(
      ["productId", "quantity", "selectedColor", "selectedSize"].sort(),
    );
  });

  it("rejects an over-long variant string", () => {
    expect(() =>
      parseCreatePaymentIntentRequest(
        validBody({ items: [{ productId: "p1", quantity: 1, selectedColor: "x".repeat(41) }] }),
      ),
    ).toThrow();
  });
});
