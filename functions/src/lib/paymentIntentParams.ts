import { ORDER_CURRENCY, PAYMENT_INTENT_PHASE_TAG } from "../config";

/**
 * The EXACT parameter object `createPaymentIntent` passes to
 * `stripe.paymentIntents.create`.
 *
 * Extracted so the Phase 8.13.4 sweep can reconcile a session whose
 * PaymentIntent id was never persisted: re-issuing this identical call with
 * the same deterministic idempotency key (`stripeIdempotencyKeyFor`) makes
 * Stripe return the PaymentIntent that was already created. Stripe rejects a
 * repeated idempotency key that carries DIFFERENT parameters, so the two call
 * sites MUST build the params the same way - hence this single builder.
 *
 * Pure apart from importing two constants.
 */
export interface PaymentIntentCreateParams {
  amount: number;
  currency: string;
  payment_method_types: string[];
  description: string;
  metadata: Record<string, string>;
}

export function buildPaymentIntentCreateParams(args: {
  sessionId: string;
  amountMinor: number;
  firebaseUserId: string;
}): PaymentIntentCreateParams {
  return {
    amount: args.amountMinor,
    currency: ORDER_CURRENCY,
    payment_method_types: ["card"],
    description: `TWin AR order (session ${args.sessionId.slice(0, 12)})`,
    metadata: {
      checkoutSessionId: args.sessionId,
      firebaseUserId: args.firebaseUserId,
      appPhase: PAYMENT_INTENT_PHASE_TAG,
    },
  };
}
