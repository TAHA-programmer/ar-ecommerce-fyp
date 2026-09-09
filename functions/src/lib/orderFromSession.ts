/**
 * Build the final `orders/{id}` and `payments/{id}` document maps from an
 * AUTHORITATIVE checkout-session snapshot.
 *
 * The webhook never trusts event metadata for prices or order contents
 * (webhook point 5) - everything here comes from the session document that
 * `createPaymentIntent` wrote server-side under a Firestore transaction.
 *
 * Shapes match `order_firestore_mapper.dart` / `payment_firestore_mapper.dart`
 * exactly (the Flutter read side), and the values satisfy
 * `firestore.rules`' `isValidOrderCreate` / `isValidPaymentCreate` invariants
 * (`paymentMethod == 'stripeCard'`, `paymentStatus == 'paid'`,
 * `orderStatus == 'pending'`, `total == subtotal + deliveryFee - discount`,
 * `discount <= subtotal + deliveryFee`, monetary ceiling) even though the
 * Admin-SDK write bypasses those rules.
 *
 * Pure apart from the delivery-window constants.
 */

export const DELIVERY_WINDOW_START_DAYS = 7;
export const DELIVERY_WINDOW_END_DAYS = 14;
const DAY_MS = 24 * 60 * 60 * 1000;

const MAX_MONETARY_RUPEES = 10_000_000;

export interface OrderItemMap {
  productId: string;
  productName: string;
  imagePath: string;
  imageSource: string;
  quantity: number;
  selectedSize: string | null;
  selectedColor: string | null;
  unitPrice: number;
  lineTotal: number;
}

export type SessionOrderBuildResult =
  | { ok: true; items: OrderItemMap[] }
  | { ok: false; reason: string };

function str(v: unknown): string {
  return typeof v === "string" ? v : "";
}
function strOrNull(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : null;
}
function intOrNaN(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) ? v : Number.NaN;
}

/** Map `session.items[]` (CheckoutSessionLineItem shape) to `orders/{id}.items[]`. */
export function buildOrderItems(sessionItems: unknown): SessionOrderBuildResult {
  if (!Array.isArray(sessionItems) || sessionItems.length === 0 || sessionItems.length > 50) {
    return { ok: false, reason: "items_not_a_1_to_50_list" };
  }
  const items: OrderItemMap[] = [];
  for (let i = 0; i < sessionItems.length; i++) {
    const raw = sessionItems[i];
    if (!raw || typeof raw !== "object") {
      return { ok: false, reason: `items[${i}]_not_an_object` };
    }
    const line = raw as Record<string, unknown>;
    const productId = str(line.productId);
    const quantity = intOrNaN(line.quantity);
    const unitPrice = intOrNaN(line.unitPriceRupees);
    const lineTotal = intOrNaN(line.lineTotalRupees);
    if (
      productId.length === 0 ||
      !Number.isInteger(quantity) ||
      quantity < 1 ||
      !Number.isInteger(unitPrice) ||
      unitPrice < 0 ||
      !Number.isInteger(lineTotal) ||
      lineTotal < 0
    ) {
      return { ok: false, reason: `items[${i}]_malformed` };
    }
    items.push({
      productId,
      productName: str(line.productName),
      imagePath: str(line.imagePath),
      imageSource: str(line.imageSource) || "network",
      quantity,
      selectedSize: strOrNull(line.selectedSize),
      selectedColor: strOrNull(line.selectedColor),
      unitPrice,
      lineTotal,
    });
  }
  return { ok: true, items };
}

export type SessionTotalsResult =
  | { ok: true; subtotal: number; deliveryFee: number; discount: number; total: number }
  | { ok: false; reason: string };

export function readSessionTotals(session: Record<string, unknown>): SessionTotalsResult {
  const subtotal = intOrNaN(session.subtotal);
  const deliveryFee = intOrNaN(session.deliveryFee);
  const discount = intOrNaN(session.discount);
  const total = intOrNaN(session.total);
  for (const [k, v] of Object.entries({ subtotal, deliveryFee, discount, total })) {
    if (!Number.isInteger(v) || v < 0 || v > MAX_MONETARY_RUPEES) {
      return { ok: false, reason: `${k}_out_of_range` };
    }
  }
  if (discount > subtotal + deliveryFee) {
    return { ok: false, reason: "discount_exceeds_subtotal_plus_delivery" };
  }
  if (total !== subtotal + deliveryFee - discount) {
    return { ok: false, reason: "total_invariant_violated" };
  }
  return { ok: true, subtotal, deliveryFee, discount, total };
}

const REQUIRED_ADDRESS_KEYS = [
  "id",
  "label",
  "fullName",
  "phoneNumber",
  "addressLine1",
  "addressLine2",
  "city",
  "provinceOrState",
  "postalCode",
  "isDefault",
];

export function readDeliveryAddressSnapshot(
  session: Record<string, unknown>,
): { ok: true; address: Record<string, unknown> } | { ok: false; reason: string } {
  const addr = session.deliveryAddressSnapshot;
  if (!addr || typeof addr !== "object") {
    return { ok: false, reason: "delivery_address_missing" };
  }
  const keys = Object.keys(addr as object).sort();
  if (JSON.stringify(keys) !== JSON.stringify([...REQUIRED_ADDRESS_KEYS].sort())) {
    return { ok: false, reason: "delivery_address_shape" };
  }
  return { ok: true, address: addr as Record<string, unknown> };
}

export type OrderPaymentDocs =
  | {
      ok: true;
      orderDoc: Record<string, unknown>;
      paymentDoc: Record<string, unknown>;
    }
  | { ok: false; reason: string };

/**
 * Build both documents. `serverTimestamp` is the Firestore
 * `FieldValue.serverTimestamp()` sentinel; `deliveryStart` / `deliveryEnd`
 * are `Timestamp`s computed by the caller from `nowMs`.
 */
export function buildOrderAndPaymentDocs(params: {
  session: Record<string, unknown>;
  orderId: string;
  paymentId: string;
  serverTimestamp: unknown;
  deliveryStart: unknown;
  deliveryEnd: unknown;
}): OrderPaymentDocs {
  const { session, orderId, paymentId } = params;

  const userId = str(session.userId);
  if (userId.length === 0) {
    return { ok: false, reason: "session_userId_missing" };
  }

  const itemsResult = buildOrderItems(session.items);
  if (!itemsResult.ok) {
    return { ok: false, reason: itemsResult.reason };
  }
  const totals = readSessionTotals(session);
  if (!totals.ok) {
    return { ok: false, reason: totals.reason };
  }
  const address = readDeliveryAddressSnapshot(session);
  if (!address.ok) {
    return { ok: false, reason: address.reason };
  }

  const orderDoc: Record<string, unknown> = {
    userId,
    paymentId,
    items: itemsResult.items,
    orderDate: params.serverTimestamp,
    subtotal: totals.subtotal,
    deliveryFee: totals.deliveryFee,
    discount: totals.discount,
    total: totals.total,
    paymentMethod: "stripeCard",
    paymentStatus: "paid",
    orderStatus: "pending",
    deliveryAddress: address.address,
    estimatedDeliveryStart: params.deliveryStart,
    estimatedDeliveryEnd: params.deliveryEnd,
  };

  const paymentDoc: Record<string, unknown> = {
    userId,
    orderId,
    amount: totals.total,
    method: "stripeCard",
    status: "paid",
    createdAt: params.serverTimestamp,
  };

  return { ok: true, orderDoc, paymentDoc };
}

export function deliveryWindowMillis(nowMs: number): { startMs: number; endMs: number } {
  return {
    startMs: nowMs + DELIVERY_WINDOW_START_DAYS * DAY_MS,
    endMs: nowMs + DELIVERY_WINDOW_END_DAYS * DAY_MS,
  };
}
