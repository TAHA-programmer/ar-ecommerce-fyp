import assert from "node:assert/strict";
import { test } from "node:test";

import { computeFavoriteCounts, computeUnitsSold, mergeStats } from "./lib.mjs";

test("computeUnitsSold sums quantity by product, skipping cancelled orders", () => {
  const m = computeUnitsSold([
    { orderStatus: "delivered", items: [{ productId: "p1", quantity: 2 }, { productId: "p2", quantity: 1 }] },
    { orderStatus: "pending", items: [{ productId: "p1", quantity: 3 }] },
    { orderStatus: "cancelled", items: [{ productId: "p1", quantity: 100 }] },
    { orderStatus: "shipped", items: [{ productId: "p3", quantity: 0 }, { productId: "", quantity: 5 }] },
  ]);
  assert.equal(m.get("p1"), 5);
  assert.equal(m.get("p2"), 1);
  assert.equal(m.has("p3"), false);
  assert.equal(m.size, 2);
});

test("computeUnitsSold tolerates missing/garbage input", () => {
  assert.equal(computeUnitsSold(undefined).size, 0);
  assert.equal(computeUnitsSold([null, {}, { items: "x" }]).size, 0);
});

test("computeFavoriteCounts counts each (product,user) once and lists voters", () => {
  const { counts, voters } = computeFavoriteCounts([
    { productId: "p1", uid: "u1" },
    { productId: "p1", uid: "u2" },
    { productId: "p1", uid: "u1" }, // duplicate — ignored
    { productId: "p2", uid: "u1" },
    { productId: "", uid: "u9" },
  ]);
  assert.equal(counts.get("p1"), 2);
  assert.equal(counts.get("p2"), 1);
  assert.equal(voters.length, 3);
});

test("mergeStats produces one row per product with both metrics", () => {
  const merged = mergeStats(
    new Map([["p1", 5], ["p2", 2]]),
    new Map([["p1", 3], ["p3", 1]]),
  );
  assert.deepEqual(merged.get("p1"), { unitsSold: 5, favoriteCount: 3 });
  assert.deepEqual(merged.get("p2"), { unitsSold: 2, favoriteCount: 0 });
  assert.deepEqual(merged.get("p3"), { unitsSold: 0, favoriteCount: 1 });
});

test("re-running the pure aggregation is idempotent (recompute, not increment)", () => {
  const orders = [{ orderStatus: "delivered", items: [{ productId: "p1", quantity: 4 }] }];
  assert.equal(computeUnitsSold(orders).get("p1"), 4);
  assert.equal(computeUnitsSold(orders).get("p1"), 4); // same, not 8
});
