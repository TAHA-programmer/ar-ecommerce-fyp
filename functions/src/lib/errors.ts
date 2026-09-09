import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

/**
 * Typed, customer-safe callable errors for `createPaymentIntent`.
 *
 * Every error carries:
 *   - a gRPC `HttpsError` code (what the Flutter `cloud_functions` SDK sees),
 *   - a stable machine `appCode` in `details.appCode` (what the app switches
 *     on to render a specific message / per-line hint),
 *   - a short, already-customer-safe `message`.
 *
 * Internal detail (Stripe error `type`/`code`, stack traces, the secret key,
 * raw request echoes) is NEVER placed in `message` or `details` - it only
 * ever goes to structured logs via `firebase-functions/logger`, and even
 * there Stripe errors are reduced to `{ type, code, statusCode }`.
 */

export type AppErrorCode =
  | "UNAUTHENTICATED"
  | "INVALID_REQUEST"
  | "ADDRESS_NOT_FOUND"
  | "ADDRESS_INCOMPLETE"
  | "PRODUCT_UNAVAILABLE"
  | "VARIANT_UNAVAILABLE"
  | "OUT_OF_STOCK"
  | "INSUFFICIENT_STOCK"
  | "ORDER_TOTAL_INVALID"
  | "CHECKOUT_ALREADY_COMPLETED"
  | "CHECKOUT_ATTEMPT_CLOSED"
  | "CHECKOUT_EXPIRED"
  | "FORBIDDEN"
  | "PAYMENT_PROVIDER_ERROR"
  | "PAYMENT_AMOUNT_TOO_SMALL"
  | "RESERVATION_CONFLICT"
  | "INTERNAL";

type GrpcCode = ConstructorParameters<typeof HttpsError>[0];

function make(
  grpc: GrpcCode,
  appCode: AppErrorCode,
  message: string,
  extra?: Record<string, unknown>,
): HttpsError {
  return new HttpsError(grpc, message, { appCode, ...(extra ?? {}) });
}

export const errUnauthenticated = (): HttpsError =>
  make("unauthenticated", "UNAUTHENTICATED", "You must be signed in to check out.");

export const errInvalidRequest = (message: string): HttpsError =>
  make("invalid-argument", "INVALID_REQUEST", message);

export const errAddressNotFound = (): HttpsError =>
  make(
    "not-found",
    "ADDRESS_NOT_FOUND",
    "We couldn't find that delivery address on your account.",
  );

export const errAddressIncomplete = (): HttpsError =>
  make(
    "failed-precondition",
    "ADDRESS_INCOMPLETE",
    "That delivery address is missing required details. Please edit it and try again.",
  );

export const errProductUnavailable = (productId: string, title?: string): HttpsError =>
  make(
    "failed-precondition",
    "PRODUCT_UNAVAILABLE",
    `${title ?? "An item in your cart"} is no longer available.`,
    { productId },
  );

export const errVariantUnavailable = (productId: string, title?: string): HttpsError =>
  make(
    "failed-precondition",
    "VARIANT_UNAVAILABLE",
    `The selected option for ${title ?? "an item in your cart"} is no longer available.`,
    { productId },
  );

export const errOutOfStock = (productId: string, title: string): HttpsError =>
  make("failed-precondition", "OUT_OF_STOCK", `${title} is out of stock.`, { productId });

export const errInsufficientStock = (
  productId: string,
  title: string,
  available: number,
  requested: number,
): HttpsError =>
  make(
    "failed-precondition",
    "INSUFFICIENT_STOCK",
    `Only ${available} of ${title} left - you asked for ${requested}.`,
    { productId, available, requested },
  );

export const errOrderTotalInvalid = (): HttpsError =>
  make(
    "failed-precondition",
    "ORDER_TOTAL_INVALID",
    "This order total can't be processed. Please review your cart.",
  );

export const errCheckoutAlreadyCompleted = (): HttpsError =>
  make(
    "failed-precondition",
    "CHECKOUT_ALREADY_COMPLETED",
    "This checkout has already been completed.",
  );

export const errCheckoutAttemptClosed = (): HttpsError =>
  make(
    "failed-precondition",
    "CHECKOUT_ATTEMPT_CLOSED",
    "This checkout attempt is closed. Please start a new checkout.",
  );

export const errCheckoutExpired = (): HttpsError =>
  make(
    "failed-precondition",
    "CHECKOUT_EXPIRED",
    "Your checkout reservation expired. Please try again.",
  );

export const errForbiddenSession = (): HttpsError =>
  make("permission-denied", "FORBIDDEN", "You don't have access to this checkout session.");

export const errPaymentProvider = (): HttpsError =>
  make(
    "unavailable",
    "PAYMENT_PROVIDER_ERROR",
    "We couldn't reach the payment provider. Your cart is unchanged - please try again.",
  );

export const errPaymentAmountTooSmall = (): HttpsError =>
  make(
    "failed-precondition",
    "PAYMENT_AMOUNT_TOO_SMALL",
    "This order total is below the minimum for card payment.",
  );

export const errReservationConflict = (): HttpsError =>
  make(
    "aborted",
    "RESERVATION_CONFLICT",
    "Something changed while we were setting up your checkout. Please try again.",
  );

export const errInternal = (
  message = "Something went wrong setting up your payment. Please try again.",
): HttpsError => make("internal", "INTERNAL", message);

/**
 * Map an error thrown by the Stripe SDK to a customer-safe `HttpsError`.
 * Logs a redacted `{ type, code, statusCode }` summary only - never the raw
 * error object, never `message` (which can echo request fields), never the
 * key.
 */
export function mapStripeError(err: unknown): HttpsError {
  const e = (err ?? {}) as {
    type?: string;
    code?: string;
    statusCode?: number;
    rawType?: string;
  };
  logger.error("createPaymentIntent: Stripe PaymentIntent call failed", {
    stripeType: e.type ?? e.rawType,
    stripeCode: e.code,
    statusCode: e.statusCode,
  });

  if (e.code === "amount_too_small") {
    return errPaymentAmountTooSmall();
  }
  if (e.type === "StripeAuthenticationError") {
    // The bound STRIPE_SECRET_KEY is wrong/rotated/unset. Operational, not
    // the customer's problem - do not leak that detail to the client.
    logger.error(
      "createPaymentIntent: Stripe authentication failed - STRIPE_SECRET_KEY may be misconfigured",
    );
    return errInternal("Card payment is temporarily unavailable. Please try again later.");
  }
  if (
    e.type === "StripeConnectionError" ||
    e.type === "StripeAPIError" ||
    e.statusCode === 429 ||
    (typeof e.statusCode === "number" && e.statusCode >= 500)
  ) {
    return errPaymentProvider();
  }
  if (e.type === "StripeInvalidRequestError" || e.type === "StripeIdempotencyError") {
    return errInternal("We couldn't set up this payment. Please try again.");
  }
  return errPaymentProvider();
}
