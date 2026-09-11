import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

/**
 * Typed, customer-safe callable errors for `generateTryOn` (Phase 9.3 Stage 4).
 *
 * Mirrors `../errors.ts`'s shape exactly (gRPC code + a stable `appCode` in
 * `details.appCode` + an already customer-safe `message`) so the Flutter side
 * can reuse the same switch-on-`appCode` pattern the checkout errors use.
 * Kept as its own module (not merged into `../errors.ts`) because the two
 * domains' error sets are unrelated and a VTO change should never risk the
 * Stripe checkout error surface.
 *
 * Internal detail (provider HTTP status/body, stack traces, the API key) is
 * NEVER placed in `message` or `details` - only ever in structured logs via
 * `firebase-functions/logger`, and even there the provider response body is
 * never logged verbatim (§10 "no image bytes or URLs in logs").
 */

export type VtoAppErrorCode =
  | "UNAUTHENTICATED"
  | "INVALID_REQUEST"
  | "CONSENT_REQUIRED"
  | "PRODUCT_UNAVAILABLE"
  | "PRODUCT_NOT_ELIGIBLE"
  | "VARIANT_UNAVAILABLE"
  | "GARMENT_UNAVAILABLE"
  | "FORBIDDEN"
  | "SESSION_ATTEMPT_CLOSED"
  | "SESSION_IN_PROGRESS"
  | "RATE_LIMITED"
  | "GLOBAL_LIMIT_REACHED"
  | "PHOTO_MISSING"
  | "PHOTO_INVALID"
  | "PROVIDER_UNAVAILABLE"
  | "PROVIDER_REFUSED"
  | "TIMEOUT"
  | "INTERNAL";

type GrpcCode = ConstructorParameters<typeof HttpsError>[0];

function make(
  grpc: GrpcCode,
  appCode: VtoAppErrorCode,
  message: string,
  extra?: Record<string, unknown>,
): HttpsError {
  return new HttpsError(grpc, message, { appCode, ...(extra ?? {}) });
}

export const errUnauthenticated = (): HttpsError =>
  make("unauthenticated", "UNAUTHENTICATED", "You must be signed in to use Virtual Try-On.");

export const errInvalidRequest = (message: string): HttpsError =>
  make("invalid-argument", "INVALID_REQUEST", message);

export const errConsentRequired = (): HttpsError =>
  make(
    "failed-precondition",
    "CONSENT_REQUIRED",
    "Please confirm the Virtual Try-On consent before continuing.",
  );

export const errProductUnavailable = (): HttpsError =>
  make("failed-precondition", "PRODUCT_UNAVAILABLE", "This product is no longer available.");

export const errProductNotEligible = (): HttpsError =>
  make(
    "failed-precondition",
    "PRODUCT_NOT_ELIGIBLE",
    "Virtual Try-On isn't available for this product.",
  );

export const errVariantUnavailable = (): HttpsError =>
  make(
    "failed-precondition",
    "VARIANT_UNAVAILABLE",
    "The selected colour or size isn't available for this product.",
  );

export const errGarmentUnavailable = (): HttpsError =>
  make(
    "failed-precondition",
    "GARMENT_UNAVAILABLE",
    "A try-on image isn't configured for this colour yet.",
  );

export const errForbiddenSession = (): HttpsError =>
  make("permission-denied", "FORBIDDEN", "You don't have access to this try-on session.");

export const errSessionAttemptClosed = (): HttpsError =>
  make(
    "failed-precondition",
    "SESSION_ATTEMPT_CLOSED",
    "That try-on attempt has ended. Please start a new one.",
  );

export const errSessionInProgress = (): HttpsError =>
  make(
    "aborted",
    "SESSION_IN_PROGRESS",
    "A preview is already being generated for this request. Please wait.",
  );

export const errSessionConflict = (): HttpsError =>
  make(
    "aborted",
    "SESSION_IN_PROGRESS",
    "Something changed while we were setting up your preview. Please try again.",
  );

export const errRateLimited = (): HttpsError =>
  make(
    "resource-exhausted",
    "RATE_LIMITED",
    "You've reached the try-on limit for now. Please try again later.",
  );

export const errGlobalLimitReached = (): HttpsError =>
  make(
    "resource-exhausted",
    "GLOBAL_LIMIT_REACHED",
    "Virtual Try-On is at capacity right now. Please try again later.",
  );

export const errPhotoMissing = (): HttpsError =>
  make(
    "failed-precondition",
    "PHOTO_MISSING",
    "We couldn't find your photo. Please take or choose one and try again.",
  );

export const errPhotoInvalid = (): HttpsError =>
  make(
    "invalid-argument",
    "PHOTO_INVALID",
    "That photo couldn't be used. Please try a clear JPEG or PNG photo.",
  );

export const errProviderUnavailable = (): HttpsError =>
  make(
    "unavailable",
    "PROVIDER_UNAVAILABLE",
    "We couldn't generate a preview right now. Please try again.",
  );

export const errProviderRefused = (): HttpsError =>
  make(
    "failed-precondition",
    "PROVIDER_REFUSED",
    "We couldn't generate a preview for this photo. Please try a different photo.",
  );

export const errTimeout = (): HttpsError =>
  make("deadline-exceeded", "TIMEOUT", "Generating your preview took too long. Please try again.");

export const errInternal = (
  message = "Something went wrong generating your preview. Please try again.",
): HttpsError => make("internal", "INTERNAL", message);

/** Log a redacted summary of an unexpected error - never the raw error, a
 *  stack trace, request echoes, or the provider response body. */
export function logUnexpected(context: string, err: unknown, extra?: Record<string, unknown>): void {
  logger.error(context, {
    name: (err as { name?: unknown })?.name,
    code: (err as { code?: unknown })?.code,
    ...(extra ?? {}),
  });
}
