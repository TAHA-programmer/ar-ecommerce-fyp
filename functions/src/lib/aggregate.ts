/**
 * Aggregate requested quantities by `productId` across every cart line.
 *
 * Two lines that are different colour/size variants of the same product must
 * be checked against - and decremented from - a single stock number
 * together; a per-line check would let each pass the full-stock test
 * independently and oversell. This mirrors the client's Phase 8.11
 * `CheckoutViewModel` aggregation, but here it is the authoritative gate.
 *
 * Pure (no imports).
 */
export function aggregateQuantitiesByProduct(
  items: ReadonlyArray<{ productId: string; quantity: number }>,
): Map<string, number> {
  const totals = new Map<string, number>();
  for (const item of items) {
    totals.set(item.productId, (totals.get(item.productId) ?? 0) + item.quantity);
  }
  return totals;
}
