import { describe, expect, it } from "vitest";

import {
  favoriteChangeKind,
  isCancelTransition,
  soldQuantitiesFromItems,
} from "../productStats";

describe("soldQuantitiesFromItems", () => {
  it("aggregates quantity by productId across lines (variants collapse)", () => {
    const map = soldQuantitiesFromItems([
      { productId: "p1", quantity: 2, selectedColor: "red" },
      { productId: "p1", quantity: 3, selectedColor: "blue" },
      { productId: "p2", quantity: 1 },
    ]);
    expect(map.get("p1")).toBe(5);
    expect(map.get("p2")).toBe(1);
    expect(map.size).toBe(2);
  });

  it("drops malformed / non-positive / id-less lines", () => {
    const map = soldQuantitiesFromItems([
      { productId: "", quantity: 5 },
      { productId: "p1", quantity: 0 },
      { productId: "p2", quantity: -4 },
      { productId: "p3", quantity: "x" },
      { productId: "p4", quantity: 2 },
      null,
      42,
    ]);
    expect([...map.entries()]).toEqual([["p4", 2]]);
  });

  it("returns an empty map for a non-array", () => {
    expect(soldQuantitiesFromItems(undefined).size).toBe(0);
    expect(soldQuantitiesFromItems({}).size).toBe(0);
  });
});

describe("isCancelTransition", () => {
  it("is true only for a non-cancelled → cancelled move", () => {
    expect(isCancelTransition("pending", "cancelled")).toBe(true);
    expect(isCancelTransition("shipped", "cancelled")).toBe(true);
    expect(isCancelTransition("cancelled", "cancelled")).toBe(false);
    expect(isCancelTransition("pending", "confirmed")).toBe(false);
    expect(isCancelTransition("shipped", "delivered")).toBe(false);
  });
});

describe("favoriteChangeKind", () => {
  it("maps create → added, delete → removed, everything else → null", () => {
    expect(favoriteChangeKind(false, true)).toBe("added");
    expect(favoriteChangeKind(true, false)).toBe("removed");
    expect(favoriteChangeKind(true, true)).toBeNull(); // update (never happens)
    expect(favoriteChangeKind(false, false)).toBeNull();
  });
});
