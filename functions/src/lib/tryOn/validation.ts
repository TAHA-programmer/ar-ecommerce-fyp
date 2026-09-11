import { errConsentRequired, errInvalidRequest } from "./errors";

/**
 * Strict validation of the `generateTryOn` request body (Phase 9.3 Stage 4).
 *
 * Everything the client sends is treated as hostile: it may only carry a
 * product reference, a colour key, an optional size hint, an idempotency key
 * and an explicit consent flag. It may NEVER carry the garment asset path,
 * the provider, prices, or another user's id - all of that is resolved
 * server-side from the authoritative `products/{id}` document and the
 * caller's own auth token. Anything not in the allow-list below is rejected
 * with a clean `invalid-argument`.
 */

export const MAX_ID_LENGTH = 200;
export const MAX_VARIANT_LENGTH = 40;
export const MIN_IDEMPOTENCY_KEY_LENGTH = 8;

export interface ParsedGenerateTryOnRequest {
  productId: string;
  colorKey: string;
  size: string | null;
  idempotencyKey: string;
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function requireDocId(value: unknown, label: string): string {
  if (typeof value !== "string") {
    throw errInvalidRequest(`${label} is required and must be a string.`);
  }
  if (value.length === 0 || value.length > MAX_ID_LENGTH) {
    throw errInvalidRequest(`${label} must be 1-${MAX_ID_LENGTH} characters.`);
  }
  if (value.includes("/") || value === "." || value === "..") {
    throw errInvalidRequest(`${label} is malformed.`);
  }
  return value;
}

function requireVariant(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0 || value.length > MAX_VARIANT_LENGTH) {
    throw errInvalidRequest(`${label} is required and must be a short string.`);
  }
  return value;
}

function normalizeOptionalVariant(value: unknown, label: string): string | null {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "string" || value.length > MAX_VARIANT_LENGTH) {
    throw errInvalidRequest(`${label} must be a short string or null.`);
  }
  return value;
}

export function parseGenerateTryOnRequest(data: unknown): ParsedGenerateTryOnRequest {
  if (!isPlainObject(data)) {
    throw errInvalidRequest("Request body must be an object.");
  }

  const productId = requireDocId(data.productId, "productId");
  const colorKey = requireVariant(data.colorKey, "colorKey");
  const size = normalizeOptionalVariant(data.size, "size");

  const idempotencyKey = data.idempotencyKey;
  if (
    typeof idempotencyKey !== "string" ||
    idempotencyKey.length < MIN_IDEMPOTENCY_KEY_LENGTH ||
    idempotencyKey.length > MAX_ID_LENGTH
  ) {
    throw errInvalidRequest(
      `idempotencyKey is required and must be ${MIN_IDEMPOTENCY_KEY_LENGTH}-${MAX_ID_LENGTH} characters.`,
    );
  }

  // D5: consent must be given explicitly on THIS request - `=== true` only;
  // a truthy-but-not-boolean value (a stale cached "1", a string) is refused.
  if (data.consent !== true) {
    throw errConsentRequired();
  }

  return { productId, colorKey, size, idempotencyKey };
}
