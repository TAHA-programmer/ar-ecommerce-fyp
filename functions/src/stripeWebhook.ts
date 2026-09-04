import { onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import { FUNCTIONS_REGION, stripeSecretKey, stripeWebhookSecret } from "./config";
import {
  closeFailedOrCancelledPayment,
  finalizeSucceededPayment,
  refundOrphanPaidSession,
} from "./lib/finalize";
import {
  getStripePaymentApi,
  stripeWebhookVerifier,
  type StripePaymentApi,
} from "./lib/stripe";
import {
  isHandledEventType,
  paymentIntentFromEvent,
  type PaymentIntentView,
} from "./lib/webhook";

/**
 * `stripeWebhook` (HTTPS) - Phase 8.13.3.
 *
 * The authoritative, Stripe-initiated half of checkout. Verifies the Stripe
 * signature against the UNTOUCHED raw request body, rejects invalid
 * signatures and live-mode events, and:
 *
 *   - `payment_intent.succeeded`     -> creates the final Order + Payment from
 *     the server-owned checkout-session snapshot and marks the session
 *     `succeeded`. Never trusts event metadata for prices / order contents.
 *   - `payment_intent.payment_failed` -> CANCELS the PaymentIntent first
 *     (Phase 8.13.4 point 5, so it can never later succeed), then restores
 *     every reserved quantity exactly once and marks the session `failed`.
 *   - `payment_intent.canceled`      -> restores every reserved quantity
 *     exactly once and marks the session `failed`.
 *
 * If a payment genuinely succeeds AFTER its reservation was released
 * (`needs_refund`), an idempotent sandbox refund is issued so the customer
 * is never left charged without an order (Phase 8.13.4 point 6).
 *
 * Idempotency: every processed Stripe `event.id` is recorded in the
 * server-only `stripeEvents/{eventId}` ledger inside the same transaction as
 * the data change, and order/payment ids are deterministic from the
 * PaymentIntent id - so duplicate, retried and out-of-order deliveries are
 * all safe.
 *
 * It does NOT touch Flutter/Android, clear the cart, tighten `orders`/
 * `payments` create rules, or deploy.
 *
 * HTTP contract (what Stripe does with the status):
 *   200 - processed, ignored, or a permanent no-op (do not retry)
 *   400 - bad signature / live-mode event / not a POST (do not retry)
 *   500 - transient failure (Firestore fault) - Stripe WILL retry
 */

export interface StripeWebhookHandlerInput {
  rawBody: string | Buffer;
  signature: string | undefined;
  webhookSecret: string;
  stripe: StripePaymentApi;
  now?: () => number;
}

export interface StripeWebhookHandlerResult {
  statusCode: number;
  body: string;
}

/**
 * A short, safe response body that mirrors the `stripeEvents` ledger
 * `outcome` (e.g. `mismatch:amount`, `paid_but_reservation_lost:failed`).
 * Stripe ignores the body; this is purely for logs / dashboards / debugging.
 */
function outcomeBody(outcome: { kind: string; reason?: string; sessionStatus?: string }): string {
  const detail = outcome.reason ?? outcome.sessionStatus;
  return detail ? `${outcome.kind}:${detail}` : outcome.kind;
}

export async function stripeWebhookHandler(
  input: StripeWebhookHandlerInput,
): Promise<StripeWebhookHandlerResult> {
  // 1. Verify the Stripe signature against the raw (unmodified) body.
  let event: { id: string; type: string; livemode?: boolean; data?: { object?: unknown } };
  try {
    event = stripeWebhookVerifier().webhooks.constructEvent(
      input.rawBody,
      input.signature ?? "",
      input.webhookSecret,
    ) as typeof event;
  } catch (err) {
    logger.warn("stripeWebhook: signature verification failed", {
      errorName: (err as { name?: unknown })?.name,
    });
    return { statusCode: 400, body: "invalid signature" };
  }

  // 2. Sandbox-only enforcement.
  const livemode = event.livemode === true;
  if (livemode) {
    logger.error("stripeWebhook: rejected a LIVE-mode event on the sandbox endpoint", {
      eventId: event.id,
      type: event.type,
    });
    return { statusCode: 400, body: "live-mode events are not accepted" };
  }

  // 3. Only three event types are actioned; anything else is acknowledged.
  if (!isHandledEventType(event.type)) {
    logger.info("stripeWebhook: ignoring unhandled event type", {
      eventId: event.id,
      type: event.type,
    });
    return { statusCode: 200, body: "ignored (unhandled type)" };
  }

  const pi = paymentIntentFromEvent(event);
  if (!pi) {
    logger.error("stripeWebhook: event has no usable PaymentIntent payload", {
      eventId: event.id,
      type: event.type,
    });
    return { statusCode: 200, body: "ignored (no PaymentIntent)" };
  }

  const checkoutSessionId = pi.metadata.checkoutSessionId;
  if (!checkoutSessionId) {
    logger.error("stripeWebhook: PaymentIntent has no checkoutSessionId metadata", {
      eventId: event.id,
      type: event.type,
      paymentIntentId: pi.id,
    });
    return { statusCode: 200, body: "ignored (no checkoutSessionId metadata)" };
  }

  const nowMs = (input.now ?? Date.now)();

  try {
    if (event.type === "payment_intent.succeeded") {
      const outcome = await finalizeSucceededPayment({
        eventId: event.id,
        eventType: event.type,
        livemode,
        pi,
        checkoutSessionId,
        nowMs,
      });

      if (outcome.kind === "needs_refund") {
        // Phase 8.13.4 point 6 - paid AFTER the reservation was released.
        await refundOrphanPaidSession({
          eventId: event.id,
          eventType: event.type,
          livemode,
          pi,
          checkoutSessionId,
          sessionStatus: outcome.sessionStatus,
          stripe: input.stripe,
        });
        const body = `refunded_reservation_lost:${outcome.sessionStatus}`;
        logger.info("stripeWebhook: success event processed", {
          eventId: event.id,
          paymentIntentId: pi.id,
          checkoutSessionId,
          outcome: body,
        });
        return { statusCode: 200, body };
      }

      const body = outcomeBody(outcome);
      logger.info("stripeWebhook: success event processed", {
        eventId: event.id,
        paymentIntentId: pi.id,
        checkoutSessionId,
        outcome: body,
      });
      return { statusCode: 200, body };
    }

    // payment_failed | canceled
    const outcome = await closeFailedOrCancelledPayment({
      eventId: event.id,
      eventType: event.type,
      livemode,
      pi,
      checkoutSessionId,
      stripe: input.stripe,
    });
    const body = outcomeBody(outcome);
    logger.info("stripeWebhook: failure/cancel event processed", {
      eventId: event.id,
      type: event.type,
      paymentIntentId: pi.id,
      checkoutSessionId,
      outcome: body,
    });
    return { statusCode: 200, body };
  } catch (err) {
    // Transaction fault (Firestore unavailable, contention exhausted, an
    // unexpected throw). Nothing was committed - the transaction is atomic.
    // Return 500 so Stripe retries with backoff.
    logger.error("stripeWebhook: transaction failed, asking Stripe to retry", {
      eventId: event.id,
      type: event.type,
      paymentIntentId: pi.id,
      checkoutSessionId,
      errorName: (err as { name?: unknown })?.name,
      errorCode: (err as { code?: unknown })?.code,
    });
    return { statusCode: 500, body: "temporary error - please retry" };
  }
}

export const stripeWebhook = onRequest(
  {
    region: FUNCTIONS_REGION,
    // STRIPE_WEBHOOK_SECRET: verify the signature. STRIPE_SECRET_KEY: cancel a
    // still-open PaymentIntent before restoring stock (point 5), and refund a
    // payment that landed after its reservation was released (point 6).
    secrets: [stripeWebhookSecret, stripeSecretKey],
    memory: "256MiB",
    timeoutSeconds: 30,
    maxInstances: 10,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("method not allowed");
      return;
    }
    const rawBody: Buffer | string = req.rawBody ?? Buffer.from("");
    const signature = req.get("stripe-signature") ?? undefined;
    const result = await stripeWebhookHandler({
      rawBody,
      signature,
      webhookSecret: stripeWebhookSecret.value(),
      stripe: getStripePaymentApi(),
    });
    res.status(result.statusCode).send(result.body);
  },
);

export type { PaymentIntentView };
