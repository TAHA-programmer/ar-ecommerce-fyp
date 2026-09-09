import { FieldValue, Timestamp, type DocumentSnapshot } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {
  stripeIdempotencyKeyFor,
  timestampToMillis,
} from "./checkoutSession";
import {
  finalizeSucceededPayment,
  refundOrphanPaidSession,
  restoreMapFromSession,
  toStr,
} from "./finalize";
import {
  db,
  checkoutSessionDoc,
  productDoc,
  stripeEventDoc,
  COLLECTIONS,
} from "./firestore";
import { buildPaymentIntentCreateParams } from "./paymentIntentParams";
import { productStockQuantity } from "./product";
import { classifyPaymentIntentStatus } from "./stripeStatus";
import type { StripePaymentApi, StripePaymentIntentLike } from "./stripe";
import { buildStripeEventRecord } from "./webhook";

/**
 * Phase 8.13.4 - the expired-reservation sweep.
 *
 * `sweepExpiredReservations` queries a bounded batch of `reserved` sessions
 * whose `expiresAt` has passed (using the `(status, expiresAt)` composite
 * index) and processes each in isolation. Per session, it inspects the
 * AUTHORITATIVE Stripe PaymentIntent before touching stock:
 *
 *   succeeded    -> finalize the order/payment (never restore)
 *   in_progress  -> defer (could still succeed)
 *   canceled     -> restore stock, mark session `expired`
 *   cancellable  -> cancel the PaymentIntent, confirm, THEN restore + `expired`
 *   unknown      -> defer
 *
 * Every mutation re-checks `status === 'reserved' && expiresAt <= now` inside
 * its final transaction, so overlapping sweeps / retries / a racing webhook
 * can never restore stock twice or after a success.
 */

const SWEEP_EVENT_TYPE = "scheduler.sweep";

export interface SweepSummary {
  scannedAt: number;
  batchSize: number;
  scanned: number;
  hadMore: boolean;
  outcomes: Record<string, number>;
  errors: number;
}

export type SweepOutcome =
  | { kind: "finalized" }
  | { kind: "refunded_reservation_lost" }
  | { kind: "released" }
  | { kind: "deferred_in_progress" }
  | { kind: "deferred_unknown_status" }
  | { kind: "deferred_cancel_incomplete" }
  | { kind: "skipped_not_expired_reserved" }
  | { kind: "no_payment_intent" }
  | { kind: "mismatch" }
  | { kind: "session_corrupt" };

export async function sweepExpiredReservations(args: {
  stripe: StripePaymentApi;
  nowMs: number;
  batchSize: number;
}): Promise<SweepSummary> {
  const cutoff = Timestamp.fromMillis(args.nowMs);
  const snap = await db()
    .collection(COLLECTIONS.checkoutSessions)
    .where("status", "==", "reserved")
    .where("expiresAt", "<=", cutoff)
    .limit(args.batchSize)
    .get();

  const settled = await Promise.allSettled(
    snap.docs.map((doc) =>
      processExpiredSession({
        sessionId: doc.id,
        session: (doc.data() ?? {}) as Record<string, unknown>,
        stripe: args.stripe,
        nowMs: args.nowMs,
      }),
    ),
  );

  const outcomes: Record<string, number> = {};
  let errors = 0;
  for (const r of settled) {
    if (r.status === "fulfilled") {
      outcomes[r.value.kind] = (outcomes[r.value.kind] ?? 0) + 1;
    } else {
      errors += 1;
      logger.error("releaseExpiredReservations: a session threw and was skipped (isolated)", {
        errorName: (r.reason as { name?: unknown })?.name,
      });
    }
  }

  const summary: SweepSummary = {
    scannedAt: args.nowMs,
    batchSize: args.batchSize,
    scanned: snap.size,
    hadMore: snap.size === args.batchSize,
    outcomes,
    errors,
  };
  logger.info("releaseExpiredReservations: sweep complete", summary);
  return summary;
}

async function processExpiredSession(args: {
  sessionId: string;
  session: Record<string, unknown>;
  stripe: StripePaymentApi;
  nowMs: number;
}): Promise<SweepOutcome> {
  const { sessionId, session, stripe, nowMs } = args;

  const pi = await resolvePaymentIntentForSession(sessionId, session, stripe);
  if (!pi) {
    logger.error(
      "releaseExpiredReservations: could not resolve a PaymentIntent for an expired session - left reserved for the next sweep",
      { sessionId },
    );
    return { kind: "no_payment_intent" };
  }

  const disposition = classifyPaymentIntentStatus(pi.status);

  if (disposition === "succeeded") {
    return finalizeExpiredSession(sessionId, pi, stripe, nowMs);
  }
  if (disposition === "in_progress") {
    logger.info("releaseExpiredReservations: PaymentIntent still in progress - deferring", { sessionId });
    return { kind: "deferred_in_progress" };
  }
  if (disposition === "unknown") {
    logger.warn("releaseExpiredReservations: unrecognised PaymentIntent status - deferring", {
      sessionId,
      status: pi.status,
    });
    return { kind: "deferred_unknown_status" };
  }
  if (disposition === "canceled") {
    return releaseExpiredSession(sessionId, pi, nowMs);
  }

  // cancellable -> cancel THEN release (only if the cancel is confirmed).
  let latest: StripePaymentIntentLike;
  try {
    latest = await stripe.cancel(pi.id);
  } catch (err) {
    logger.warn("releaseExpiredReservations: cancel failed, re-checking PaymentIntent", {
      sessionId,
      errorName: (err as { name?: unknown })?.name,
    });
    try {
      latest = await stripe.retrieve(pi.id);
    } catch {
      return { kind: "deferred_cancel_incomplete" };
    }
  }

  const latestDisposition = classifyPaymentIntentStatus(latest.status);
  if (latestDisposition === "succeeded") {
    return finalizeExpiredSession(sessionId, latest, stripe, nowMs);
  }
  if (latestDisposition === "canceled") {
    return releaseExpiredSession(sessionId, latest, nowMs);
  }
  // Not confirmed cancelled (in_progress / still cancellable / unknown) -
  // NEVER restore. Next sweep retries the cancel; a late success is caught
  // by the webhook -> refund backstop.
  logger.warn(
    "releaseExpiredReservations: PaymentIntent not confirmed cancelled after a cancel attempt - deferring",
    { sessionId, status: latest.status },
  );
  return { kind: "deferred_cancel_incomplete" };
}

/**
 * Resolve the session's PaymentIntent. If the id was never persisted (the
 * Phase 8.13.2 best-effort `session.update` can fail), re-issue the identical
 * `paymentIntents.create` call with the deterministic idempotency key - Stripe
 * returns the PaymentIntent that was already created.
 */
async function resolvePaymentIntentForSession(
  sessionId: string,
  session: Record<string, unknown>,
  stripe: StripePaymentApi,
): Promise<StripePaymentIntentLike | null> {
  const stored = session.stripePaymentIntentId;
  if (typeof stored === "string" && stored.length > 0) {
    try {
      return await stripe.retrieve(stored);
    } catch {
      logger.warn("releaseExpiredReservations: stored PaymentIntent id not retrievable", { sessionId });
      return null;
    }
  }

  const amountMinor = session.amountMinor;
  const userId = session.userId;
  if (typeof amountMinor !== "number" || !Number.isFinite(amountMinor) || typeof userId !== "string") {
    logger.warn("releaseExpiredReservations: session lacks amount/user for PI reconciliation", { sessionId });
    return null;
  }
  try {
    const pi = await stripe.create(
      buildPaymentIntentCreateParams({ sessionId, amountMinor, firebaseUserId: userId }),
      { idempotencyKey: stripeIdempotencyKeyFor(sessionId) },
    );
    await checkoutSessionDoc(sessionId)
      .update({ stripePaymentIntentId: pi.id, updatedAt: FieldValue.serverTimestamp() })
      .catch(() => undefined);
    return pi;
  } catch {
    logger.warn("releaseExpiredReservations: PaymentIntent reconciliation failed", { sessionId });
    return null;
  }
}

async function finalizeExpiredSession(
  sessionId: string,
  pi: StripePaymentIntentLike,
  stripe: StripePaymentApi,
  nowMs: number,
): Promise<SweepOutcome> {
  const ledgerEventId = `sweep_finalize_${pi.id}`;
  const outcome = await finalizeSucceededPayment({
    eventId: ledgerEventId,
    eventType: SWEEP_EVENT_TYPE,
    livemode: false,
    pi,
    checkoutSessionId: sessionId,
    nowMs,
  });

  if (outcome.kind === "needs_refund") {
    await refundOrphanPaidSession({
      eventId: ledgerEventId,
      eventType: SWEEP_EVENT_TYPE,
      livemode: false,
      pi,
      checkoutSessionId: sessionId,
      sessionStatus: outcome.sessionStatus,
      stripe,
    });
    return { kind: "refunded_reservation_lost" };
  }
  if (outcome.kind === "finalized" || outcome.kind === "already_finalized" || outcome.kind === "duplicate_event") {
    return { kind: "finalized" };
  }
  if (outcome.kind === "mismatch") {
    logger.warn("releaseExpiredReservations: PI/session mismatch during finalize - skipping", { sessionId });
    return { kind: "mismatch" };
  }
  logger.error("releaseExpiredReservations: finalize returned an unexpected outcome", {
    sessionId,
    outcome: outcome.kind,
  });
  return { kind: "session_corrupt" };
}

async function releaseExpiredSession(
  sessionId: string,
  pi: StripePaymentIntentLike | null,
  nowMs: number,
): Promise<SweepOutcome> {
  const ledgerRef = stripeEventDoc(`sweep_release_${sessionId}`);

  return db().runTransaction<SweepOutcome>(async (tx) => {
    // ---- READS + re-check (Phase 8.13.4 point 4) ----
    const ledgerSnap = await tx.get(ledgerRef);
    if (ledgerSnap.exists) {
      return { kind: "skipped_not_expired_reserved" };
    }

    const sessionSnap = await tx.get(checkoutSessionDoc(sessionId));
    if (!sessionSnap.exists) {
      return { kind: "session_corrupt" };
    }
    const session = (sessionSnap.data() ?? {}) as Record<string, unknown>;
    const status = toStr(session.status);
    const expMs = timestampToMillis(session.expiresAt);

    if (status !== "reserved" || expMs === null || expMs > nowMs) {
      // Another sweep / the webhook already handled it, or the clock moved.
      return { kind: "skipped_not_expired_reserved" };
    }

    const restoreMap = restoreMapFromSession(session);
    const productIds = [...restoreMap.keys()];
    const productSnaps: DocumentSnapshot[] =
      productIds.length > 0 ? await tx.getAll(...productIds.map((id) => productDoc(id))) : [];
    const productById = new Map(productSnaps.map((s) => [s.id, s]));

    // ---- WRITES ----
    tx.update(checkoutSessionDoc(sessionId), {
      status: "expired",
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const [productId, qty] of restoreMap) {
      const snap = productById.get(productId);
      if (!snap || !snap.exists) {
        logger.warn("releaseExpiredReservations: product deleted, cannot restore stock", {
          sessionId,
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
    tx.create(
      ledgerRef,
      buildStripeEventRecord({
        eventId: `sweep_release_${sessionId}`,
        type: SWEEP_EVENT_TYPE,
        livemode: false,
        paymentIntentId: pi ? pi.id : null,
        checkoutSessionId: sessionId,
        outcome: "released_expired",
        serverTimestamp: FieldValue.serverTimestamp(),
      }),
    );
    return { kind: "released" };
  });
}
