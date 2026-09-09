import Stripe from "stripe";

import { stripeSecretKey } from "../config";

/**
 * Lazily-constructed Stripe client + the narrow, injectable boundary the
 * checkout functions actually use.
 *
 * The secret key VALUE comes only from the `STRIPE_SECRET_KEY` Secret Manager
 * secret at runtime (each function that needs Stripe declares
 * `secrets: [stripeSecretKey]`, which makes `.value()` resolve). It is never
 * read from source, a committed `.env`, `process.env` defaults, or a log.
 *
 * The Stripe API version is intentionally NOT pinned so it tracks the
 * installed `stripe` package's default (which its TypeScript types are
 * generated against).
 */

/** The PaymentIntent fields the checkout functions read back. */
export interface StripePaymentIntentLike {
  id: string;
  client_secret: string | null;
  status: string;
  amount: number;
  currency: string;
  metadata: Record<string, string | undefined>;
}

export interface StripeRefundLike {
  id: string;
  status: string;
}

/** The only Stripe surface the checkout functions touch - mockable in tests. */
export interface StripePaymentApi {
  create(
    params: {
      amount: number;
      currency: string;
      payment_method_types?: string[];
      metadata?: Record<string, string>;
      description?: string;
    },
    options?: { idempotencyKey?: string },
  ): Promise<StripePaymentIntentLike>;
  retrieve(id: string): Promise<StripePaymentIntentLike>;
  /** Cancel a PaymentIntent that is not yet paid. Throws if it already succeeded / was cancelled. */
  cancel(id: string, options?: { idempotencyKey?: string }): Promise<StripePaymentIntentLike>;
  /** Refund a succeeded PaymentIntent. Idempotent via `options.idempotencyKey`. */
  createRefund(
    params: { paymentIntentId: string },
    options?: { idempotencyKey?: string },
  ): Promise<StripeRefundLike>;
}

function normalizeMetadata(meta: unknown): Record<string, string | undefined> {
  const out: Record<string, string | undefined> = {};
  if (meta && typeof meta === "object") {
    for (const [k, v] of Object.entries(meta as Record<string, unknown>)) {
      if (typeof v === "string") out[k] = v;
    }
  }
  return out;
}

function toLike(pi: Stripe.PaymentIntent): StripePaymentIntentLike {
  return {
    id: pi.id,
    client_secret: pi.client_secret,
    status: pi.status,
    amount: typeof pi.amount === "number" ? pi.amount : Number.NaN,
    currency: typeof pi.currency === "string" ? pi.currency : "",
    metadata: normalizeMetadata(pi.metadata),
  };
}

let client: Stripe | null = null;

export function getStripe(): Stripe {
  if (client) {
    return client;
  }
  const key = stripeSecretKey.value();
  if (!key || key.length === 0) {
    throw new Error(
      "STRIPE_SECRET_KEY is not configured. Set it with `firebase functions:secrets:set STRIPE_SECRET_KEY`.",
    );
  }
  client = new Stripe(key);
  return client;
}

/**
 * Stripe client used ONLY to verify inbound webhook signatures.
 *
 * `stripe.webhooks.constructEvent()` verifies with the webhook SIGNING SECRET
 * via HMAC-SHA256 - it never touches the API key. The placeholder string
 * below satisfies the `Stripe` constructor and is never sent anywhere.
 */
let webhookVerifierClient: Stripe | null = null;

export function stripeWebhookVerifier(): Stripe {
  if (!webhookVerifierClient) {
    webhookVerifierClient = new Stripe("sk_placeholder_used_only_for_webhook_hmac_verification");
  }
  return webhookVerifierClient;
}

/** Adapt the real Stripe client to the narrow {@link StripePaymentApi}. */
export function getStripePaymentApi(): StripePaymentApi {
  const stripe = getStripe();
  return {
    async create(params, options) {
      const pi = await stripe.paymentIntents.create(
        {
          amount: params.amount,
          currency: params.currency,
          payment_method_types: params.payment_method_types,
          metadata: params.metadata,
          description: params.description,
        },
        options?.idempotencyKey ? { idempotencyKey: options.idempotencyKey } : undefined,
      );
      return toLike(pi);
    },
    async retrieve(id) {
      return toLike(await stripe.paymentIntents.retrieve(id));
    },
    async cancel(id, options) {
      const pi = await stripe.paymentIntents.cancel(
        id,
        undefined,
        options?.idempotencyKey ? { idempotencyKey: options.idempotencyKey } : undefined,
      );
      return toLike(pi);
    },
    async createRefund({ paymentIntentId }, options) {
      const refund = await stripe.refunds.create(
        { payment_intent: paymentIntentId },
        options?.idempotencyKey ? { idempotencyKey: options.idempotencyKey } : undefined,
      );
      return { id: refund.id, status: refund.status ?? "unknown" };
    },
  };
}

/** Test seam: drop the memoised clients. */
export function resetStripeClientForTests(): void {
  client = null;
  webhookVerifierClient = null;
}
