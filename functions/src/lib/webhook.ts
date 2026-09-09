import { createHash } from "node:crypto";

/**
 * Pure helpers for the `stripeWebhook` function: deterministic id derivation,
 * PaymentIntent extraction, session-vs-event cross-checking, and the event
 * ledger record shape.
 *
 * Dependency-free apart from `node:crypto` - fully unit-tested. The Firestore
 * transactions live in `finalize.ts`; the HTTP entrypoint + signature
 * verification live in `../stripeWebhook.ts`.
 */

/** Event types this webhook acts on. Everything else is acknowledged and ignored. */
export const HANDLED_EVENT_TYPES = [
  "payment_intent.succeeded",
  "payment_intent.payment_failed",
  "payment_intent.canceled",
] as const;

export type HandledEventType = (typeof HANDLED_EVENT_TYPES)[number];

export function isHandledEventType(type: string): type is HandledEventType {
  return (HANDLED_EVENT_TYPES as readonly string[]).includes(type);
}

/**
 * Deterministic order / payment document ids derived from the Stripe
 * PaymentIntent id. Same PaymentIntent -> same ids, so a duplicate or
 * replayed `payment_intent.succeeded` can only ever `tx.create` a document
 * that already exists (which the finalize transaction detects and skips) -
 * duplicate orders / payments are structurally impossible.
 */
export function deterministicOrderId(paymentIntentId: string): string {
  return `ord_${createHash("sha256").update(`order:${paymentIntentId}`).digest("hex").slice(0, 40)}`;
}

export function deterministicPaymentId(paymentIntentId: string): string {
  return `pay_${createHash("sha256").update(`payment:${paymentIntentId}`).digest("hex").slice(0, 40)}`;
}

export interface PaymentIntentView {
  id: string;
  /** Amount in the currency's smallest unit (paisa for PKR). `NaN` if absent/wrong-typed. */
  amount: number;
  currency: string;
  metadata: Record<string, string | undefined>;
}

/**
 * Extract only the PaymentIntent fields the webhook trusts from a Stripe
 * event. Deliberately NOT the whole object - `client_secret`, charge/card
 * details etc. are never read or logged.
 */
export function paymentIntentFromEvent(event: unknown): PaymentIntentView | null {
  const obj = (event as { data?: { object?: unknown } })?.data?.object;
  if (!obj || typeof obj !== "object") {
    return null;
  }
  const pi = obj as Record<string, unknown>;
  if (typeof pi.id !== "string" || pi.id.length === 0) {
    return null;
  }
  const rawMeta = (pi.metadata ?? {}) as Record<string, unknown>;
  const metadata: Record<string, string | undefined> = {};
  for (const [k, v] of Object.entries(rawMeta)) {
    if (typeof v === "string") {
      metadata[k] = v;
    }
  }
  return {
    id: pi.id,
    amount: typeof pi.amount === "number" ? pi.amount : Number.NaN,
    currency: typeof pi.currency === "string" ? pi.currency : "",
    metadata,
  };
}

export type SessionMismatch =
  | "metadata_session_id"
  | "payment_intent_id"
  | "user"
  | "currency"
  | "amount";

/**
 * Cross-check the server-owned checkout session against the signed
 * PaymentIntent BEFORE any data changes (webhook point 4). Returns `null` if
 * everything matches, otherwise the first field that did not.
 *
 * `session.stripePaymentIntentId` may legitimately be `null` (the Phase
 * 8.13.2 best-effort persist can fail) - in that case the metadata
 * `checkoutSessionId` is the authoritative link and the id check is skipped
 * (finalize back-fills it).
 */
export function verifySessionMatchesPaymentIntent(
  session: Record<string, unknown>,
  pi: PaymentIntentView,
  checkoutSessionId: string,
): SessionMismatch | null {
  if (pi.metadata.checkoutSessionId !== checkoutSessionId) {
    return "metadata_session_id";
  }
  const storedPi = session.stripePaymentIntentId;
  if (typeof storedPi === "string" && storedPi.length > 0 && storedPi !== pi.id) {
    return "payment_intent_id";
  }
  if (pi.metadata.firebaseUserId !== session.userId) {
    return "user";
  }
  const sessionCurrency =
    typeof session.currency === "string" ? session.currency.toLowerCase() : "";
  if (pi.currency.toLowerCase() !== sessionCurrency) {
    return "currency";
  }
  if (!Number.isFinite(pi.amount) || pi.amount !== session.amountMinor) {
    return "amount";
  }
  return null;
}

export interface StripeEventRecord {
  eventId: string;
  type: string;
  livemode: boolean;
  paymentIntentId: string | null;
  checkoutSessionId: string | null;
  outcome: string;
  /** Firestore `serverTimestamp()` sentinel at runtime. */
  processedAt: unknown;
}

export function buildStripeEventRecord(params: {
  eventId: string;
  type: string;
  livemode: boolean;
  paymentIntentId: string | null;
  checkoutSessionId: string | null;
  outcome: string;
  serverTimestamp: unknown;
}): StripeEventRecord {
  return {
    eventId: params.eventId,
    type: params.type,
    livemode: params.livemode,
    paymentIntentId: params.paymentIntentId,
    checkoutSessionId: params.checkoutSessionId,
    outcome: params.outcome,
    processedAt: params.serverTimestamp,
  };
}
