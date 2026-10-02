import type { CustomerNotificationType } from "./types";

/**
 * Deterministic dedupe keys (plan §4.8). The customer inbox row id IS the
 * key, so `create()` raising ALREADY_EXISTS == "duplicate trigger delivery,
 * do nothing". Admin keys address the server-only `notificationEvents`
 * ledger. Pure.
 */

const KEY_PART = /^[A-Za-z0-9_.:-]{1,200}$/;
const MAX_KEY_LENGTH = 500;

export class DedupeKeyError extends Error {}

function part(value: string, name: string): string {
  if (typeof value !== "string" || !KEY_PART.test(value)) {
    throw new DedupeKeyError(`invalid dedupe key part: ${name}`);
  }
  return value;
}

function finish(key: string): string {
  if (key.length > MAX_KEY_LENGTH) throw new DedupeKeyError("dedupe key too long");
  return key;
}

/** `order_confirmed_<orderId>` etc. Each order status is a one-way step in
 *  the lifecycle graph, so (status, orderId) is unique per real event. */
export function customerOrderKey(
  type: Extract<
    CustomerNotificationType,
    "order_placed" | "order_confirmed" | "order_shipped" | "order_delivered" | "order_cancelled"
  >,
  orderId: string,
): string {
  return finish(`${type}_${part(orderId, "orderId")}`);
}

/** `refund_<paymentIntentId>` - one refund notice per PaymentIntent. */
export function refundKey(paymentIntentId: string): string {
  return finish(`refund_${part(paymentIntentId, "paymentIntentId")}`);
}

/** `<type>_<reviewId>_<moderatedAtMillis>` - a later, genuinely new
 *  moderation action on the same review gets a new key. */
export function reviewModerationKey(
  type: Extract<CustomerNotificationType, "review_hidden" | "review_rejected" | "review_restored">,
  reviewId: string,
  moderatedAtMs: number,
): string {
  if (!Number.isSafeInteger(moderatedAtMs) || moderatedAtMs <= 0) {
    throw new DedupeKeyError("invalid moderatedAtMs");
  }
  return finish(`${type}_${part(reviewId, "reviewId")}_${moderatedAtMs}`);
}

export const adminKeys = {
  newOrder: (orderId: string) => finish(`admin_order_${part(orderId, "orderId")}`),
  lowStock: (productId: string) => finish(`admin_lowstock_${part(productId, "productId")}`),
  outOfStock: (productId: string) => finish(`admin_oos_${part(productId, "productId")}`),
  reviewFlagged: (reviewId: string) => finish(`admin_flag_${part(reviewId, "reviewId")}`),
  anomaly: (stripeEventId: string) => finish(`admin_anomaly_${part(stripeEventId, "eventId")}`),
} as const;

/** Whether an admin ledger alert is allowed again: no prior send, or the
 *  cooldown has fully elapsed. A `lastSentMs` in the future (clock skew)
 *  is treated as still cooling down. */
export function cooldownElapsed(
  lastSentMs: number | null | undefined,
  nowMs: number,
  cooldownMs: number,
): boolean {
  if (lastSentMs == null || !Number.isFinite(lastSentMs)) return true;
  return nowMs - lastSentMs >= cooldownMs;
}
