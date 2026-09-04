import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";

import {
  FUNCTIONS_REGION,
  RESERVATION_SWEEP_BATCH_SIZE,
  RESERVATION_SWEEP_SCHEDULE,
  stripeSecretKey,
} from "./config";
import { getStripePaymentApi } from "./lib/stripe";
import { sweepExpiredReservations, type SweepSummary } from "./lib/sweep";

/**
 * `releaseExpiredReservations` (scheduled) - Phase 8.13.4.
 *
 * Every 5 minutes, processes a bounded batch of `reserved` checkout sessions
 * whose reservation window has expired. For each it inspects the authoritative
 * Stripe PaymentIntent and, only when a payment can no longer succeed,
 * restores the reserved stock exactly once and marks the session `expired`;
 * a succeeded payment is finalized into an order instead; a payment still in
 * flight is left for the next run. See `lib/sweep.ts` for the state machine.
 *
 * Bound to `STRIPE_SECRET_KEY` only (retrieve / cancel / refund). It does NOT
 * verify webhook signatures, so it does not need `STRIPE_WEBHOOK_SECRET`.
 */
export const releaseExpiredReservations = onSchedule(
  {
    region: FUNCTIONS_REGION,
    schedule: RESERVATION_SWEEP_SCHEDULE,
    secrets: [stripeSecretKey],
    memory: "256MiB",
    timeoutSeconds: 120,
    // One sweep at a time. Overlapping runs would still be idempotent (every
    // mutation re-checks session state in its transaction), but there is no
    // reason to allow them.
    maxInstances: 1,
    // Don't queue retries - the work is idempotent and the next 5-minute run
    // picks up anything missed.
    retryCount: 0,
  },
  async () => {
    let summary: SweepSummary;
    try {
      summary = await sweepExpiredReservations({
        stripe: getStripePaymentApi(),
        nowMs: Date.now(),
        batchSize: RESERVATION_SWEEP_BATCH_SIZE,
      });
    } catch (err) {
      logger.error("releaseExpiredReservations: sweep failed", {
        errorName: (err as { name?: unknown })?.name,
        errorCode: (err as { code?: unknown })?.code,
      });
      return;
    }
    logger.info("releaseExpiredReservations: run finished", {
      scanned: summary.scanned,
      hadMore: summary.hadMore,
      errors: summary.errors,
      outcomes: summary.outcomes,
    });
  },
);
