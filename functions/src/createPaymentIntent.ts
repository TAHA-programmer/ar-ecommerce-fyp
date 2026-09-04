import { onCall } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import { FUNCTIONS_REGION, stripeSecretKey } from "./config";
import { buildPaymentIntentCreateParams } from "./lib/paymentIntentParams";
import {
  sessionIdFor,
  stripeIdempotencyKeyFor,
  type CheckoutSessionStatus,
} from "./lib/checkoutSession";
import {
  errCheckoutAlreadyCompleted,
  errCheckoutAttemptClosed,
  errCheckoutExpired,
  errForbiddenSession,
  errInternal,
  errUnauthenticated,
  mapStripeError,
} from "./lib/errors";
import type { OrderTotalsRupees } from "./lib/pricing";
import { releaseReservation, reserveOrClassify } from "./lib/reservation";
import {
  checkoutSessionDoc,
} from "./lib/firestore";
import { getStripePaymentApi, type StripePaymentApi } from "./lib/stripe";
import { parseCreatePaymentIntentRequest } from "./lib/validation";
import { FieldValue } from "firebase-admin/firestore";

/**
 * `createPaymentIntent` (callable) - Phase 8.13.2.
 *
 * Trusted server-side checkout foundation. Requires an authenticated Firebase
 * user; accepts ONLY product references, variant labels, quantities, an
 * address reference and an idempotency key; resolves authoritative
 * products/prices/stock and the user-owned address from Firestore; aggregates
 * by productId; atomically reserves (decrements) stock and writes a
 * server-owned `checkoutSessions` document; then creates a PKR Stripe
 * sandbox PaymentIntent. On any Stripe failure it compensates by restoring
 * the reserved stock and closing the session, so there is never an abandoned
 * reservation or an orphan PaymentIntent from a failed attempt.
 *
 * It does NOT create `orders`/`payments` (Phase 8.13.3), handle webhooks
 * (8.13.3) or run scheduled cleanup (8.13.4).
 */

export interface CreatePaymentIntentResult {
  checkoutSessionId: string;
  paymentIntentClientSecret: string;
  amount: number;
  currency: string;
  status: "reserved";
  expiresAt: number;
  totals: OrderTotalsRupees;
}

export interface CreatePaymentIntentHandlerInput {
  authUid: string | undefined;
  data: unknown;
  stripe: StripePaymentApi;
  /** Injectable clock for tests. */
  now?: () => number;
}

async function compensate(
  sessionId: string,
  status: Extract<CheckoutSessionStatus, "failed" | "expired">,
): Promise<void> {
  try {
    const result = await releaseReservation(sessionId, status);
    logger.info("createPaymentIntent: reservation released", { sessionId, status, result });
  } catch (err) {
    // Compensation itself failed -> the session stays `reserved` with
    // `expiresAt` set; the Phase 8.13.4 scheduled sweep is the backstop.
    logger.error(
      "createPaymentIntent: compensation FAILED - session left reserved for the scheduled sweep",
      { sessionId, status, name: (err as { name?: unknown })?.name },
    );
  }
}

export async function createPaymentIntentHandler(
  input: CreatePaymentIntentHandlerInput,
): Promise<CreatePaymentIntentResult> {
  const nowMs = (input.now ?? Date.now)();

  if (!input.authUid) {
    throw errUnauthenticated();
  }
  const uid = input.authUid;

  const request = parseCreatePaymentIntentRequest(input.data);
  const sessionId = sessionIdFor(uid, request.idempotencyKey);

  const outcome = await reserveOrClassify({ uid, sessionId, request, nowMs });

  switch (outcome.kind) {
    case "foreign":
      throw errForbiddenSession();
    case "already_completed":
      throw errCheckoutAlreadyCompleted();
    case "attempt_closed":
      throw errCheckoutAttemptClosed();
    case "expired":
      await compensate(sessionId, "expired");
      throw errCheckoutExpired();

    case "has_payment_intent": {
      // Retry after we already created the PaymentIntent - just hand back a
      // fresh client secret. No new reservation, no new PaymentIntent.
      let pi;
      try {
        pi = await input.stripe.retrieve(outcome.paymentIntentId);
      } catch (err) {
        throw mapStripeError(err);
      }
      if (pi.status === "canceled") {
        await compensate(sessionId, "failed");
        throw errCheckoutAttemptClosed();
      }
      if (!pi.client_secret) {
        throw errInternal();
      }
      return buildResult(sessionId, pi.client_secret, outcome);
    }

    case "created":
    case "needs_payment_intent": {
      const stripeIdempotencyKey = stripeIdempotencyKeyFor(sessionId);
      let pi;
      try {
        pi = await input.stripe.create(
          buildPaymentIntentCreateParams({
            sessionId,
            amountMinor: outcome.amountMinor,
            firebaseUserId: uid,
          }),
          { idempotencyKey: stripeIdempotencyKey },
        );
      } catch (err) {
        // Compensate ONLY when THIS call created the reservation. On the
        // `needs_payment_intent` retry path the stock was decremented by the
        // original attempt and the session is still validly `reserved` -
        // restoring here would double-restore; the client just retries.
        if (outcome.kind === "created") {
          await compensate(sessionId, "failed");
        }
        throw mapStripeError(err);
      }

      if (!pi.client_secret) {
        if (outcome.kind === "created") {
          await compensate(sessionId, "failed");
        }
        throw errInternal();
      }

      // Persist the PaymentIntent id. Best-effort: if it fails the client
      // still has a usable client secret, the PaymentIntent carries
      // `checkoutSessionId` in metadata for the Phase 8.13.3 webhook, and a
      // retry re-enters `needs_payment_intent` and reconciles.
      try {
        await checkoutSessionDoc(sessionId).update({
          stripePaymentIntentId: pi.id,
          updatedAt: FieldValue.serverTimestamp(),
        });
      } catch (err) {
        logger.warn(
          "createPaymentIntent: could not persist stripePaymentIntentId (non-fatal, will reconcile on retry)",
          { sessionId, name: (err as { name?: unknown })?.name },
        );
      }

      return buildResult(sessionId, pi.client_secret, outcome);
    }
  }
}

function buildResult(
  sessionId: string,
  clientSecret: string,
  outcome: {
    totals: OrderTotalsRupees;
    amountMinor: number;
    currency: string;
    expiresAtMs: number;
  },
): CreatePaymentIntentResult {
  return {
    checkoutSessionId: sessionId,
    paymentIntentClientSecret: clientSecret,
    amount: outcome.amountMinor,
    currency: outcome.currency,
    status: "reserved",
    expiresAt: outcome.expiresAtMs,
    totals: outcome.totals,
  };
}

export const createPaymentIntent = onCall(
  {
    region: FUNCTIONS_REGION,
    secrets: [stripeSecretKey],
    memory: "256MiB",
    timeoutSeconds: 30,
    maxInstances: 10,
  },
  (request) =>
    createPaymentIntentHandler({
      authUid: request.auth?.uid,
      data: request.data,
      stripe: getStripePaymentApi(),
    }),
);
