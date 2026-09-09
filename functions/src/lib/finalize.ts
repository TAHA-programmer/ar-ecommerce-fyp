import { FieldValue, Timestamp, type DocumentSnapshot } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import { aggregateQuantitiesByProduct } from "./aggregate";
import { applyUnitsSoldOnFinalize } from "./productStats";
import { stripeRefundIdempotencyKeyFor } from "./checkoutSession";
import { buildOrderAndPaymentDocs, deliveryWindowMillis } from "./orderFromSession";
import { productStockQuantity } from "./product";
import { classifyPaymentIntentStatus } from "./stripeStatus";
import {
  db,
  checkoutSessionDoc,
  orderDoc,
  paymentDoc,
  productDoc,
  stripeEventDoc,
} from "./firestore";
import type { StripePaymentApi } from "./stripe";
import {
  buildStripeEventRecord,
  deterministicOrderId,
  deterministicPaymentId,
  verifySessionMatchesPaymentIntent,
  type PaymentIntentView,
} from "./webhook";

/**
 * The shared Firestore lifecycle transactions, used by BOTH `stripeWebhook`
 * and the Phase 8.13.4 `releaseExpiredReservations` sweep:
 *
 *   - `finalizeSucceededPayment`      : create the final Order + Payment from
 *     the authoritative session snapshot and mark the session `succeeded`.
 *     Idempotent (ledger + deterministic order/payment ids). If the session's
 *     reservation was already released it returns `needs_refund` instead.
 *   - `refundOrphanPaidSession`       : Phase 8.13.4 point 6 - a genuine
 *     payment landed after its reservation was released and no order can
 *     safely be created, so issue an idempotent sandbox refund. The customer
 *     is never left charged without an order.
 *   - `closeFailedOrCancelledPayment` : restore every reserved quantity
 *     EXACTLY ONCE and mark the session `failed`. Phase 8.13.4 point 5: on
 *     `payment_intent.payment_failed` the PaymentIntent is cancelled FIRST so
 *     it can never later succeed for the same reservation.
 */

export const RESERVED = "reserved";
export const SUCCEEDED = "succeeded";
export const FAILED = "failed";
export const EXPIRED = "expired";

export type FinalizeOutcome =
  | { kind: "duplicate_event" }
  | { kind: "session_missing" }
  | { kind: "mismatch"; reason: string }
  | { kind: "already_finalized" }
  | { kind: "finalized"; orderId: string; paymentId: string }
  | { kind: "needs_refund"; sessionStatus: string }
  | { kind: "inconsistent_order_payment" }
  | { kind: "session_corrupt"; reason: string };

export type CloseOutcome =
  | { kind: "duplicate_event" }
  | { kind: "session_missing" }
  | { kind: "mismatch"; reason: string }
  | { kind: "ignored_already_succeeded" }
  | { kind: "already_released" }
  | { kind: "released" }
  | { kind: "deferred_pi_could_still_succeed" };

export type RefundOutcome =
  | { kind: "refunded"; refundId: string }
  | { kind: "refund_already_recorded" };

export function toStr(v: unknown): string {
  return typeof v === "string" ? v : "";
}

export function restoreMapFromSession(session: Record<string, unknown>): Map<string, number> {
  const items = Array.isArray(session.items) ? (session.items as Record<string, unknown>[]) : [];
  return aggregateQuantitiesByProduct(
    items
      .map((it) => ({
        productId: typeof it.productId === "string" ? it.productId : "",
        quantity: typeof it.quantity === "number" ? it.quantity : 0,
      }))
      .filter((it) => it.productId.length > 0 && it.quantity > 0),
  );
}

function eventRecordFactory(args: {
  eventId: string;
  eventType: string;
  livemode: boolean;
  pi: PaymentIntentView;
  checkoutSessionId: string;
}) {
  return (outcome: string) =>
    buildStripeEventRecord({
      eventId: args.eventId,
      type: args.eventType,
      livemode: args.livemode,
      paymentIntentId: args.pi.id,
      checkoutSessionId: args.checkoutSessionId,
      outcome,
      serverTimestamp: FieldValue.serverTimestamp(),
    });
}

// ---------------------------------------------------------------------------
// finalize
// ---------------------------------------------------------------------------

export async function finalizeSucceededPayment(args: {
  eventId: string;
  eventType: string;
  livemode: boolean;
  pi: PaymentIntentView;
  checkoutSessionId: string;
  nowMs: number;
}): Promise<FinalizeOutcome> {
  const { eventId, pi, checkoutSessionId, nowMs } = args;
  const orderId = deterministicOrderId(pi.id);
  const paymentId = deterministicPaymentId(pi.id);
  const eventRecord = eventRecordFactory(args);

  return db().runTransaction<FinalizeOutcome>(async (tx) => {
    // ---- READS ----
    const eventSnap = await tx.get(stripeEventDoc(eventId));
    if (eventSnap.exists) {
      return { kind: "duplicate_event" };
    }

    const sessionSnap = await tx.get(checkoutSessionDoc(checkoutSessionId));
    if (!sessionSnap.exists) {
      tx.create(stripeEventDoc(eventId), eventRecord("session_missing"));
      return { kind: "session_missing" };
    }
    const session = (sessionSnap.data() ?? {}) as Record<string, unknown>;

    const mismatch = verifySessionMatchesPaymentIntent(session, pi, checkoutSessionId);
    if (mismatch) {
      tx.create(stripeEventDoc(eventId), eventRecord(`mismatch:${mismatch}`));
      return { kind: "mismatch", reason: mismatch };
    }

    const status = toStr(session.status);

    if (status === SUCCEEDED) {
      tx.create(stripeEventDoc(eventId), eventRecord("already_finalized"));
      return { kind: "already_finalized" };
    }

    if (status === FAILED || status === EXPIRED) {
      // The reservation was already released. We must NOT restore-then-order.
      // The caller issues an idempotent refund (`refundOrphanPaidSession`).
      // Deliberately NO ledger write here - so a retry re-enters and the
      // refund (idempotent at Stripe) is guaranteed to be attempted until
      // the ledger record lands.
      return { kind: "needs_refund", sessionStatus: status };
    }

    if (status !== RESERVED) {
      tx.create(stripeEventDoc(eventId), eventRecord(`session_corrupt:status_${status || "empty"}`));
      return { kind: "session_corrupt", reason: `status_${status || "empty"}` };
    }

    const orderSnap = await tx.get(orderDoc(orderId));
    const paymentSnap = await tx.get(paymentDoc(paymentId));

    if (orderSnap.exists !== paymentSnap.exists) {
      logger.error("finalize: inconsistent order/payment pair - manual reconciliation required", {
        eventId,
        checkoutSessionId,
        orderExists: orderSnap.exists,
        paymentExists: paymentSnap.exists,
      });
      tx.create(stripeEventDoc(eventId), eventRecord("inconsistent_order_payment"));
      return { kind: "inconsistent_order_payment" };
    }

    const window = deliveryWindowMillis(nowMs);
    const built = buildOrderAndPaymentDocs({
      session,
      orderId,
      paymentId,
      serverTimestamp: FieldValue.serverTimestamp(),
      deliveryStart: Timestamp.fromMillis(window.startMs),
      deliveryEnd: Timestamp.fromMillis(window.endMs),
    });
    if (!built.ok) {
      logger.error("finalize: cannot build a valid order from the session snapshot", {
        eventId,
        checkoutSessionId,
        reason: built.reason,
      });
      tx.create(stripeEventDoc(eventId), eventRecord(`session_corrupt:${built.reason}`));
      return { kind: "session_corrupt", reason: built.reason };
    }

    // ---- WRITES (atomic) ----
    if (!orderSnap.exists) {
      tx.create(orderDoc(orderId), built.orderDoc);
      tx.create(paymentDoc(paymentId), built.paymentDoc);
      // Phase 9.3 Stage 2 - bump the Home "units sold" ordering aggregate.
      // This whole block runs exactly once per order (guarded by the
      // `stripeEvents` ledger + the deterministic order id + this
      // `!orderSnap.exists` check), so the increment is exact.
      applyUnitsSoldOnFinalize(
        tx,
        restoreMapFromSession(session),
        FieldValue.serverTimestamp(),
      );
    }
    const sessionUpdate: Record<string, unknown> = {
      status: SUCCEEDED,
      orderId,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (session.stripePaymentIntentId == null) {
      sessionUpdate.stripePaymentIntentId = pi.id;
    }
    tx.update(checkoutSessionDoc(checkoutSessionId), sessionUpdate);
    tx.create(stripeEventDoc(eventId), eventRecord("finalized"));

    return { kind: "finalized", orderId, paymentId };
  });
}

// ---------------------------------------------------------------------------
// refund the orphan (paid, reservation already gone)
// ---------------------------------------------------------------------------

export async function refundOrphanPaidSession(args: {
  eventId: string;
  eventType: string;
  livemode: boolean;
  pi: PaymentIntentView;
  checkoutSessionId: string;
  sessionStatus: string;
  stripe: StripePaymentApi;
}): Promise<RefundOutcome> {
  const { eventId, pi, checkoutSessionId, sessionStatus, stripe } = args;
  const eventRecord = eventRecordFactory(args);

  // 1. Idempotent refund. Repeated calls with this key are a Stripe no-op.
  const refund = await stripe.createRefund(
    { paymentIntentId: pi.id },
    { idempotencyKey: stripeRefundIdempotencyKeyFor(pi.id) },
  );
  logger.error(
    "checkout: payment succeeded AFTER its reservation was released - issued an idempotent sandbox refund",
    {
      eventId,
      checkoutSessionId,
      paymentIntentId: pi.id,
      sessionStatus,
      refundStatus: refund.status,
    },
  );

  // 2. Record it (tolerating an entry a concurrent retry already wrote).
  return db().runTransaction<RefundOutcome>(async (tx) => {
    const snap = await tx.get(stripeEventDoc(eventId));
    if (snap.exists) {
      return { kind: "refund_already_recorded" };
    }
    tx.create(
      stripeEventDoc(eventId),
      eventRecord(`refunded_reservation_lost:${sessionStatus}`),
    );
    return { kind: "refunded", refundId: refund.id };
  });
}

// ---------------------------------------------------------------------------
// close a failed / cancelled attempt (restore stock exactly once)
// ---------------------------------------------------------------------------

/**
 * Ensure a PaymentIntent can never later succeed before we restore its
 * reservation's stock. Only relevant for `payment_intent.payment_failed`
 * (a `payment_intent.canceled` event means Stripe already cancelled it).
 */
async function ensurePaymentIntentClosed(
  paymentIntentId: string,
  stripe: StripePaymentApi,
): Promise<"restore_ok" | "pi_could_still_succeed"> {
  let current;
  try {
    current = await stripe.retrieve(paymentIntentId);
  } catch {
    // Can't inspect it - defer to the transaction's own session re-check and
    // the refund backstop; do NOT assume it's safe to restore.
    return "pi_could_still_succeed";
  }
  const disposition = classifyPaymentIntentStatus(current.status);
  if (disposition === "succeeded" || disposition === "in_progress" || disposition === "unknown") {
    return "pi_could_still_succeed";
  }
  if (disposition === "canceled") {
    return "restore_ok";
  }
  // cancellable -> cancel it, then confirm.
  try {
    const cancelled = await stripe.cancel(paymentIntentId);
    return classifyPaymentIntentStatus(cancelled.status) === "canceled"
      ? "restore_ok"
      : "pi_could_still_succeed";
  } catch {
    // Cancel failed - re-check. Never restore unless confirmed cancelled.
    try {
      const recheck = await stripe.retrieve(paymentIntentId);
      return classifyPaymentIntentStatus(recheck.status) === "canceled"
        ? "restore_ok"
        : "pi_could_still_succeed";
    } catch {
      return "pi_could_still_succeed";
    }
  }
}

export async function closeFailedOrCancelledPayment(args: {
  eventId: string;
  eventType: string;
  livemode: boolean;
  pi: PaymentIntentView;
  checkoutSessionId: string;
  stripe: StripePaymentApi;
}): Promise<CloseOutcome> {
  const { eventId, eventType, pi, checkoutSessionId, stripe } = args;
  const eventRecord = eventRecordFactory(args);

  // Cheap non-transactional pre-read: only call Stripe when there is a live
  // reservation AND this is a `payment_failed` (a `canceled` event means the
  // PaymentIntent is already terminal-unpaid).
  const preSnap = await checkoutSessionDoc(checkoutSessionId).get();
  const preStatus = preSnap.exists ? toStr(preSnap.data()?.status) : "";
  let closeGuard: "restore_ok" | "pi_could_still_succeed" = "restore_ok";
  if (preStatus === RESERVED && eventType === "payment_intent.payment_failed") {
    closeGuard = await ensurePaymentIntentClosed(pi.id, stripe);
  }

  return db().runTransaction<CloseOutcome>(async (tx) => {
    const eventSnap = await tx.get(stripeEventDoc(eventId));
    if (eventSnap.exists) {
      return { kind: "duplicate_event" };
    }

    const sessionSnap = await tx.get(checkoutSessionDoc(checkoutSessionId));
    if (!sessionSnap.exists) {
      tx.create(stripeEventDoc(eventId), eventRecord("session_missing"));
      return { kind: "session_missing" };
    }
    const session = (sessionSnap.data() ?? {}) as Record<string, unknown>;

    if (pi.metadata.checkoutSessionId !== checkoutSessionId) {
      tx.create(stripeEventDoc(eventId), eventRecord("mismatch:metadata_session_id"));
      return { kind: "mismatch", reason: "metadata_session_id" };
    }
    const storedPi = session.stripePaymentIntentId;
    if (typeof storedPi === "string" && storedPi.length > 0 && storedPi !== pi.id) {
      tx.create(stripeEventDoc(eventId), eventRecord("mismatch:payment_intent_id"));
      return { kind: "mismatch", reason: "payment_intent_id" };
    }

    const status = toStr(session.status);

    if (status === SUCCEEDED) {
      logger.warn("close: failure/cancel event for an already-succeeded session - ignored", {
        eventId,
        checkoutSessionId,
        paymentIntentId: pi.id,
      });
      tx.create(stripeEventDoc(eventId), eventRecord("ignored_already_succeeded"));
      return { kind: "ignored_already_succeeded" };
    }

    if (status === FAILED || status === EXPIRED) {
      tx.create(stripeEventDoc(eventId), eventRecord("already_released"));
      return { kind: "already_released" };
    }

    if (status !== RESERVED) {
      tx.create(stripeEventDoc(eventId), eventRecord(`noop_corrupt_status_${status || "empty"}`));
      return { kind: "already_released" };
    }

    // status === RESERVED
    if (closeGuard === "pi_could_still_succeed") {
      // Phase 8.13.4 point 5 - the PaymentIntent is not confirmed dead, so
      // DO NOT restore stock. A later `payment_intent.succeeded` will
      // finalize; a still-abandoned attempt is caught by the sweep.
      logger.warn("close: PaymentIntent could still succeed - deferring stock restore", {
        eventId,
        checkoutSessionId,
        paymentIntentId: pi.id,
      });
      tx.create(stripeEventDoc(eventId), eventRecord("deferred_pi_could_still_succeed"));
      return { kind: "deferred_pi_could_still_succeed" };
    }

    const restoreMap = restoreMapFromSession(session);
    const productIds = [...restoreMap.keys()];
    const productSnaps: DocumentSnapshot[] =
      productIds.length > 0 ? await tx.getAll(...productIds.map((id) => productDoc(id))) : [];
    const productById = new Map(productSnaps.map((s) => [s.id, s]));

    tx.update(checkoutSessionDoc(checkoutSessionId), {
      status: FAILED,
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const [productId, qty] of restoreMap) {
      const snap = productById.get(productId);
      if (!snap || !snap.exists) {
        logger.warn("close: product deleted since reservation, cannot restore stock", {
          checkoutSessionId,
          productId,
        });
        continue;
      }
      const current = productStockQuantity((snap.data() ?? {}) as Record<string, unknown>);
      tx.update(productDoc(productId), {
        stockQuantity: current + qty,
        lastStockUpdatedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.create(stripeEventDoc(eventId), eventRecord("released"));
    return { kind: "released" };
  });
}
