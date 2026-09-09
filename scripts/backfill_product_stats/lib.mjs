// Pure aggregation logic for the productStats backfill. No firebase-admin
// import here so `node --test` can exercise it without credentials.

/**
 * `{ productId -> Σ purchased quantity }` from a list of order documents.
 * A `cancelled` order contributes NOTHING (its units were never a real sale,
 * and the cancel trigger would otherwise also have decremented it).
 *
 * @param {Array<{orderStatus?: string, items?: any}>} orders
 * @returns {Map<string, number>}
 */
export function computeUnitsSold(orders) {
  const totals = new Map();
  for (const order of orders ?? []) {
    if (!order || order.orderStatus === "cancelled") continue;
    const items = Array.isArray(order.items) ? order.items : [];
    for (const raw of items) {
      const it = raw ?? {};
      const productId = typeof it.productId === "string" ? it.productId : "";
      const qty = typeof it.quantity === "number" ? it.quantity : 0;
      if (productId.length === 0 || !Number.isInteger(qty) || qty <= 0) continue;
      totals.set(productId, (totals.get(productId) ?? 0) + qty);
    }
  }
  return totals;
}

/**
 * `{ productId -> favourite count }` and the flat voter list, from the
 * `users/{uid}/favorites/{productId}` documents (doc ID IS the productId).
 *
 * @param {Array<{productId: string, uid: string}>} favorites
 * @returns {{ counts: Map<string, number>, voters: Array<{productId: string, uid: string}> }}
 */
export function computeFavoriteCounts(favorites) {
  const counts = new Map();
  const seenByProduct = new Map(); // productId -> Set<uid>  (delimiter-free dedup)
  const voters = [];
  for (const fav of favorites ?? []) {
    const productId = typeof fav?.productId === "string" ? fav.productId : "";
    const uid = typeof fav?.uid === "string" ? fav.uid : "";
    if (productId.length === 0 || uid.length === 0) continue;
    let seenUids = seenByProduct.get(productId);
    if (!seenUids) {
      seenUids = new Set();
      seenByProduct.set(productId, seenUids);
    }
    if (seenUids.has(uid)) continue; // a (product,user) pair counts once
    seenUids.add(uid);
    counts.set(productId, (counts.get(productId) ?? 0) + 1);
    voters.push({ productId, uid });
  }
  return { counts, voters };
}

/**
 * Merge the two aggregates into the per-product `productStats` document body.
 * @returns {Map<string, {unitsSold: number, favoriteCount: number}>}
 */
export function mergeStats(unitsSold, favoriteCounts) {
  const out = new Map();
  for (const [productId, n] of unitsSold) {
    out.set(productId, { unitsSold: n, favoriteCount: 0 });
  }
  for (const [productId, n] of favoriteCounts) {
    const cur = out.get(productId) ?? { unitsSold: 0, favoriteCount: 0 };
    cur.favoriteCount = n;
    out.set(productId, cur);
  }
  return out;
}
