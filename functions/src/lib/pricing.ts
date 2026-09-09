/**
 * Server-authoritative order pricing.
 *
 * Mirrors the current client (`CheckoutViewModel.subtotal` / `.total` +
 * `PricingConstants`) for every realistic cart, with ONE deliberate
 * correction (Phase 8.13.2): the flat discount is clamped so the Firestore
 * monetary invariants in `firestore.rules` (`isValidOrderCreate`) always
 * hold - see `computeOrderTotals`.
 *
 *   subtotal    = sum(unitPriceRupees * quantity)   (prices resolved from products/{id})
 *   deliveryFee = flat 500 rupees
 *   discount    = min(1000, subtotal + deliveryFee)   <-- clamp (see below)
 *   total       = subtotal + deliveryFee - discount   (always >= 0, invariant-exact)
 *
 * Pure (no imports, no Firebase) - fully unit-tested.
 */

/** Flat delivery fee in rupees. Mirrors `PricingConstants.deliveryFee` (500.0). */
export const DELIVERY_FEE_RUPEES = 500;

/**
 * Nominal flat order discount in rupees. Mirrors `PricingConstants.discount`
 * (1000.0). The *applied* discount is `min(this, subtotal + deliveryFee)` -
 * see `computeOrderTotals`.
 */
export const NOMINAL_DISCOUNT_RUPEES = 1000;

/**
 * Ceiling on every monetary field, in rupees. Mirrors the 10,000,000 bound
 * enforced on `subtotal`/`deliveryFee`/`discount`/`total`/`amount` in
 * `firestore.rules`.
 */
export const MAX_MONETARY_RUPEES = 10_000_000;

export interface PricedLineItem {
  productId: string;
  quantity: number;
  /** Authoritative unit price in whole rupees, resolved from `products/{id}`. */
  unitPriceRupees: number;
}

export interface OrderTotalsRupees {
  subtotal: number;
  deliveryFee: number;
  discount: number;
  total: number;
}

/**
 * Compute order totals from already-priced line items.
 *
 * Throws on an empty cart or any invalid quantity/price, and if any resulting
 * field would fall outside `[0, MAX_MONETARY_RUPEES]`.
 *
 * SMALL-CART DISCOUNT FIX (Phase 8.13.2): the client reports a flat 1000
 * discount even when `subtotal + deliveryFee < 1000`, which (a) makes
 * `total !== subtotal + deliveryFee - discount` and (b) violates
 * `firestore.rules`' `discount <= subtotal + deliveryFee`. The server clamps
 * `discount = min(NOMINAL_DISCOUNT_RUPEES, subtotal + deliveryFee)`, so
 * `total` is always `>= 0` AND exactly `subtotal + deliveryFee - discount`.
 * For every realistic cart (subtotal >= 500) the clamp is a no-op and the
 * result is identical to the client's.
 */
export function computeOrderTotals(items: PricedLineItem[]): OrderTotalsRupees {
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error("computeOrderTotals: cannot price an empty cart");
  }

  let subtotal = 0;
  for (const item of items) {
    if (!Number.isInteger(item.quantity) || item.quantity < 1) {
      throw new Error(
        `computeOrderTotals: invalid quantity for ${item.productId}: ${item.quantity}`,
      );
    }
    if (
      typeof item.unitPriceRupees !== "number" ||
      !Number.isFinite(item.unitPriceRupees) ||
      !Number.isInteger(item.unitPriceRupees) ||
      item.unitPriceRupees < 0
    ) {
      throw new Error(
        `computeOrderTotals: invalid unit price for ${item.productId}: ${item.unitPriceRupees}`,
      );
    }
    subtotal += item.unitPriceRupees * item.quantity;
  }

  const deliveryFee = DELIVERY_FEE_RUPEES;
  const discount = Math.min(NOMINAL_DISCOUNT_RUPEES, subtotal + deliveryFee);
  const total = subtotal + deliveryFee - discount;

  const totals: OrderTotalsRupees = { subtotal, deliveryFee, discount, total };
  for (const [field, value] of Object.entries(totals)) {
    if (!Number.isInteger(value) || value < 0 || value > MAX_MONETARY_RUPEES) {
      throw new Error(`computeOrderTotals: ${field} out of allowed range: ${value}`);
    }
  }
  // Invariants that firestore.rules' isValidOrderCreate will re-check server-side.
  if (totals.discount > totals.subtotal + totals.deliveryFee) {
    throw new Error("computeOrderTotals: discount exceeds subtotal + deliveryFee");
  }
  if (totals.total !== totals.subtotal + totals.deliveryFee - totals.discount) {
    throw new Error("computeOrderTotals: total does not satisfy the monetary invariant");
  }
  return totals;
}
