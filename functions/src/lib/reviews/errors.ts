import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

/**
 * Typed, customer-safe callable errors for `submitReview`/`deleteReview`/
 * `reportReview`/`moderateReview` (Ratings/Reviews v1).
 *
 * Mirrors `../errors.ts` / `../tryOn/errors.ts`'s exact shape (gRPC code + a
 * stable `appCode` in `details.appCode` + an already customer-safe
 * `message`), kept as its own module for the same reason `tryOn/errors.ts`
 * is separate from the checkout errors: an unrelated domain, so a reviews
 * change can never risk the Stripe/VTO error surfaces.
 */

export type ReviewAppErrorCode =
  | "UNAUTHENTICATED"
  | "INVALID_REQUEST"
  | "NOT_ELIGIBLE"
  | "EDIT_WINDOW_EXPIRED"
  | "REVIEW_NOT_FOUND"
  | "FORBIDDEN"
  | "ADMIN_REQUIRED"
  | "CANNOT_REPORT_OWN_REVIEW"
  | "INTERNAL";

type GrpcCode = ConstructorParameters<typeof HttpsError>[0];

function make(
  grpc: GrpcCode,
  appCode: ReviewAppErrorCode,
  message: string,
  extra?: Record<string, unknown>,
): HttpsError {
  return new HttpsError(grpc, message, { appCode, ...(extra ?? {}) });
}

export const errUnauthenticated = (): HttpsError =>
  make("unauthenticated", "UNAUTHENTICATED", "You must be signed in to do that.");

export const errInvalidRequest = (message: string): HttpsError =>
  make("invalid-argument", "INVALID_REQUEST", message);

export const errNotEligible = (): HttpsError =>
  make(
    "failed-precondition",
    "NOT_ELIGIBLE",
    "You can only review products from a delivered order.",
  );

export const errEditWindowExpired = (): HttpsError =>
  make(
    "failed-precondition",
    "EDIT_WINDOW_EXPIRED",
    "This review can no longer be edited - the 30-day edit window has passed.",
  );

export const errReviewNotFound = (): HttpsError =>
  make("not-found", "REVIEW_NOT_FOUND", "This review no longer exists.");

export const errForbidden = (): HttpsError =>
  make("permission-denied", "FORBIDDEN", "You don't have access to that review.");

export const errAdminRequired = (): HttpsError =>
  make("permission-denied", "ADMIN_REQUIRED", "Admin access is required for this action.");

export const errCannotReportOwnReview = (): HttpsError =>
  make("failed-precondition", "CANNOT_REPORT_OWN_REVIEW", "You can't report your own review.");

export const errInternal = (
  message = "Something went wrong. Please try again.",
): HttpsError => make("internal", "INTERNAL", message);

/** Logs an unexpected (non-`HttpsError`) failure with structured context,
 *  never the raw error object at top level - exact mirror of
 *  `tryOn/errors.ts`'s `logUnexpected`. */
export function logUnexpected(
  context: string,
  err: unknown,
  extra?: Record<string, unknown>,
): void {
  logger.error(context, {
    name: (err as { name?: unknown })?.name,
    code: (err as { code?: unknown })?.code,
    ...(extra ?? {}),
  });
}
