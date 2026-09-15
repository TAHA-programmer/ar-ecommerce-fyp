import {
  REVIEW_MAX_BODY_LENGTH,
  REVIEW_MAX_RATING,
  REVIEW_MAX_TITLE_LENGTH,
  REVIEW_MIN_BODY_LENGTH,
  REVIEW_MIN_RATING,
  REVIEW_MODERATION_REASON_MAX_LENGTH,
  REVIEW_REPORT_NOTE_MAX_LENGTH,
} from "../../config";
import { errInvalidRequest } from "./errors";

/**
 * Strict validation of the `submitReview` request body (Ratings/Reviews v1
 * `24_RATINGS_REVIEWS_FEEDBACK_PLAN.md` §0). Everything the client sends is
 * treated as hostile: it may only carry a product reference, a rating, an
 * optional title, and a body. It may NEVER carry the reviewer id, the
 * order id, the status, the report count, or any moderation field - all of
 * that is resolved/owned server-side. Anything malformed is rejected with a
 * clean `invalid-argument` before any Firestore read.
 */

const MAX_PRODUCT_ID_LENGTH = 200;
// A reviewId is the deterministic `{userId}_{productId}` composite id - both
// halves may independently approach MAX_PRODUCT_ID_LENGTH-scale ids, so its
// own ceiling is generous rather than a tight re-derivation of that math.
const MAX_REVIEW_ID_LENGTH = 500;

export const REPORT_REASONS = ["spam", "offensive", "fake", "other"] as const;
export type ReviewReportReason = (typeof REPORT_REASONS)[number];

export const MODERATION_ACTIONS = ["hide", "restore", "reject"] as const;
export type ModerationAction = (typeof MODERATION_ACTIONS)[number];

export interface ParsedSubmitReviewRequest {
  productId: string;
  rating: number;
  title: string | null;
  body: string;
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function requireProductId(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 || value.length > MAX_PRODUCT_ID_LENGTH) {
    throw errInvalidRequest("productId is required and must be a non-empty string.");
  }
  if (value.includes("/") || value === "." || value === "..") {
    throw errInvalidRequest("productId is malformed.");
  }
  return value;
}

function requireRating(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw errInvalidRequest("rating must be a whole number.");
  }
  if (value < REVIEW_MIN_RATING || value > REVIEW_MAX_RATING) {
    throw errInvalidRequest(
      `rating must be between ${REVIEW_MIN_RATING} and ${REVIEW_MAX_RATING}.`,
    );
  }
  return value;
}

function normalizeOptionalTitle(value: unknown): string | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") {
    throw errInvalidRequest("title must be a string.");
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > REVIEW_MAX_TITLE_LENGTH) {
    throw errInvalidRequest(`title must be at most ${REVIEW_MAX_TITLE_LENGTH} characters.`);
  }
  return trimmed;
}

function requireBody(value: unknown): string {
  if (typeof value !== "string") {
    throw errInvalidRequest("body is required and must be a string.");
  }
  const trimmed = value.trim();
  if (trimmed.length < REVIEW_MIN_BODY_LENGTH || trimmed.length > REVIEW_MAX_BODY_LENGTH) {
    throw errInvalidRequest(
      `body must be ${REVIEW_MIN_BODY_LENGTH}-${REVIEW_MAX_BODY_LENGTH} characters.`,
    );
  }
  return trimmed;
}

export function parseSubmitReviewRequest(data: unknown): ParsedSubmitReviewRequest {
  if (!isPlainObject(data)) {
    throw errInvalidRequest("Request body must be an object.");
  }
  return {
    productId: requireProductId(data.productId),
    rating: requireRating(data.rating),
    title: normalizeOptionalTitle(data.title),
    body: requireBody(data.body),
  };
}

export interface ParsedDeleteReviewRequest {
  productId: string;
}

export function parseDeleteReviewRequest(data: unknown): ParsedDeleteReviewRequest {
  if (!isPlainObject(data)) {
    throw errInvalidRequest("Request body must be an object.");
  }
  return { productId: requireProductId(data.productId) };
}

function requireReviewId(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 || value.length > MAX_REVIEW_ID_LENGTH) {
    throw errInvalidRequest("reviewId is required and must be a non-empty string.");
  }
  if (value === "." || value === "..") {
    throw errInvalidRequest("reviewId is malformed.");
  }
  return value;
}

function requireReportReason(value: unknown): ReviewReportReason {
  if (typeof value !== "string" || !REPORT_REASONS.includes(value as ReviewReportReason)) {
    throw errInvalidRequest(`reason must be one of: ${REPORT_REASONS.join(", ")}.`);
  }
  return value as ReviewReportReason;
}

function normalizeOptionalNote(value: unknown): string | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") {
    throw errInvalidRequest("note must be a string.");
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > REVIEW_REPORT_NOTE_MAX_LENGTH) {
    throw errInvalidRequest(`note must be at most ${REVIEW_REPORT_NOTE_MAX_LENGTH} characters.`);
  }
  return trimmed;
}

export interface ParsedReportReviewRequest {
  reviewId: string;
  reason: ReviewReportReason;
  note: string | null;
}

/**
 * Strict validation of the `reportReview` request body. Never carries the
 * reporter id (resolved from auth) or any count/flag - those are
 * server-owned.
 */
export function parseReportReviewRequest(data: unknown): ParsedReportReviewRequest {
  if (!isPlainObject(data)) {
    throw errInvalidRequest("Request body must be an object.");
  }
  return {
    reviewId: requireReviewId(data.reviewId),
    reason: requireReportReason(data.reason),
    note: normalizeOptionalNote(data.note),
  };
}

function requireModerationAction(value: unknown): ModerationAction {
  if (typeof value !== "string" || !MODERATION_ACTIONS.includes(value as ModerationAction)) {
    throw errInvalidRequest(`action must be one of: ${MODERATION_ACTIONS.join(", ")}.`);
  }
  return value as ModerationAction;
}

function requireModerationReason(value: unknown): string {
  if (typeof value !== "string") {
    throw errInvalidRequest("reason is required and must be a string.");
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw errInvalidRequest("reason is required for every moderation action.");
  }
  if (trimmed.length > REVIEW_MODERATION_REASON_MAX_LENGTH) {
    throw errInvalidRequest(
      `reason must be at most ${REVIEW_MODERATION_REASON_MAX_LENGTH} characters.`,
    );
  }
  return trimmed;
}

export interface ParsedModerateReviewRequest {
  reviewId: string;
  action: ModerationAction;
  reason: string;
}

/**
 * Strict validation of the `moderateReview` request body. `reason` is
 * required for EVERY action (v1 §0 decision 12: "each action requires a
 * reason") - hide, restore, and reject alike.
 */
export function parseModerateReviewRequest(data: unknown): ParsedModerateReviewRequest {
  if (!isPlainObject(data)) {
    throw errInvalidRequest("Request body must be an object.");
  }
  return {
    reviewId: requireReviewId(data.reviewId),
    action: requireModerationAction(data.action),
    reason: requireModerationReason(data.reason),
  };
}
