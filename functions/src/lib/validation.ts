import { errInvalidRequest } from "./errors";

/**
 * Strict validation of the `createPaymentIntent` request body.
 *
 * Everything the client sends is treated as hostile: it may only carry
 * product references, variant labels, quantities, an address *reference*,
 * and an idempotency key. It may NEVER carry prices, totals, stock, a user
 * id, or address contents - those are all resolved server-side from
 * authoritative Firestore documents. Anything not in the allow-list below is
 * rejected with a clean `invalid-argument`.
 *
 * Pure apart from importing the error factory.
 */

export const MAX_LINE_ITEMS = 50; // mirrors firestore.rules `items.size() <= 50`
export const MAX_QUANTITY_PER_LINE = 99; // mirrors the cart clamp (1..99)
export const MAX_ID_LENGTH = 200;
export const MIN_IDEMPOTENCY_KEY_LENGTH = 8;
export const MAX_VARIANT_LENGTH = 40;

export interface RequestLineItem {
  productId: string;
  quantity: number;
  selectedColor: string | null;
  selectedSize: string | null;
}

export interface ParsedCreatePaymentIntentRequest {
  items: RequestLineItem[];
  addressId: string;
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

function normalizeVariant(value: unknown, label: string): string | null {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "string" || value.length > MAX_VARIANT_LENGTH) {
    throw errInvalidRequest(`${label} must be a short string or null.`);
  }
  return value;
}

export function parseCreatePaymentIntentRequest(
  data: unknown,
): ParsedCreatePaymentIntentRequest {
  if (!isPlainObject(data)) {
    throw errInvalidRequest("Request body must be an object.");
  }

  const addressId = requireDocId(data.addressId, "addressId");

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

  const rawItems = data.items;
  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    throw errInvalidRequest("items must be a non-empty array.");
  }
  if (rawItems.length > MAX_LINE_ITEMS) {
    throw errInvalidRequest(`items cannot exceed ${MAX_LINE_ITEMS} lines.`);
  }

  const items: RequestLineItem[] = rawItems.map((raw, i) => {
    if (!isPlainObject(raw)) {
      throw errInvalidRequest(`items[${i}] must be an object.`);
    }
    const productId = requireDocId(raw.productId, `items[${i}].productId`);
    const quantity = raw.quantity;
    if (
      typeof quantity !== "number" ||
      !Number.isInteger(quantity) ||
      quantity < 1 ||
      quantity > MAX_QUANTITY_PER_LINE
    ) {
      throw errInvalidRequest(
        `items[${i}].quantity must be an integer between 1 and ${MAX_QUANTITY_PER_LINE}.`,
      );
    }
    return {
      productId,
      quantity,
      selectedColor: normalizeVariant(raw.selectedColor, `items[${i}].selectedColor`),
      selectedSize: normalizeVariant(raw.selectedSize, `items[${i}].selectedSize`),
    };
  });

  return { items, addressId, idempotencyKey };
}
