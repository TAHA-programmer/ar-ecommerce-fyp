import { describe, it, expect } from "vitest";

import { aggregateQuantitiesByProduct } from "../aggregate";

describe("aggregateQuantitiesByProduct", () => {
  it("sums quantity per productId across colour/size variants", () => {
    const result = aggregateQuantitiesByProduct([
      { productId: "p1", quantity: 2 },
      { productId: "p1", quantity: 3 }, // different variant, same product
      { productId: "p2", quantity: 1 },
    ]);
    expect(result.get("p1")).toBe(5);
    expect(result.get("p2")).toBe(1);
    expect(result.size).toBe(2);
  });

  it("returns an empty map for an empty list", () => {
    expect(aggregateQuantitiesByProduct([]).size).toBe(0);
  });

  it("keeps a single-line product as-is", () => {
    const result = aggregateQuantitiesByProduct([{ productId: "p1", quantity: 4 }]);
    expect(result.get("p1")).toBe(4);
  });
});
