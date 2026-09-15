import { ordersRef } from "../firestore";

/**
 * The real, server-side verified-purchase gate (Ratings/Reviews v1 §0
 * decision 1): `true` only when `uid` has an `orders` document with
 * `orderStatus == 'delivered'` whose `items[]` contains `productId`.
 *
 * Deliberately a single-equality-filter query (`where('userId', '==', uid)`)
 * plus in-memory filtering, NOT a two-field composite query - exact mirror
 * of the Flutter client's `StripeCheckoutPaymentService.recentlyPurchasedLines`
 * precedent (`24_RATINGS_REVIEWS_FEEDBACK_PLAN.md` §1). This needs no new
 * Firestore composite index, and a customer's total order count is small
 * and bounded, so scanning it in application code is efficient enough.
 *
 * Returns the qualifying order's id (for the review's audit-only `orderId`
 * field) or `null` if no such order exists. The Admin SDK bypasses
 * `firestore.rules` entirely, so THIS function - not the client's own
 * `isEligibleToReview` read - is the real, authoritative gate.
 */
export async function findQualifyingDeliveredOrder(
  uid: string,
  productId: string,
): Promise<string | null> {
  const snapshot = await ordersRef().where("userId", "==", uid).get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data.orderStatus !== "delivered") continue;
    const items = data.items;
    if (!Array.isArray(items)) continue;
    const hasProduct = items.some(
      (item) => item && typeof item === "object" && (item as Record<string, unknown>).productId === productId,
    );
    if (hasProduct) return doc.id;
  }
  return null;
}
