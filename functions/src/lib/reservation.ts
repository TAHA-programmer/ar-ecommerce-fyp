import {
  FieldValue,
  Timestamp,
  type DocumentSnapshot,
} from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import { ORDER_CURRENCY } from "../config";
import { aggregateQuantitiesByProduct } from "./aggregate";
import { buildDeliveryAddressSnapshot } from "./address";
import {
  buildReservedSessionDoc,
  classifyExistingSession,
  RESERVATION_TTL_MS,
  timestampToMillis,
  type CheckoutSessionLineItem,
  type CheckoutSessionStatus,
} from "./checkoutSession";
import { toStripeMinorUnits } from "./currency";
import {
  errAddressNotFound,
  errInsufficientStock,
  errOrderTotalInvalid,
  errOutOfStock,
  errProductUnavailable,
  errReservationConflict,
} from "./errors";
import {
  db,
  checkoutSessionDoc,
  productDoc,
  userAddressDefaultPointerDoc,
  userAddressDoc,
} from "./firestore";
import { computeOrderTotals, type OrderTotalsRupees } from "./pricing";
import {
  assertProductPurchasable,
  assertVariantAvailable,
  productMainImage,
  productPriceRupees,
  productStockQuantity,
  productTitle,
} from "./product";
import type { ParsedCreatePaymentIntentRequest } from "./validation";

/**
 * The Firestore side of `createPaymentIntent`.
 *
 *   - `reserveOrClassify`  : ONE transaction. Either (a) validates + prices +
 *     atomically creates the `reserved` session and decrements stock, or
 *     (b) sees an existing session for this (uid, key) and returns a verdict
 *     for the caller to act on (retry / already-done / expired). No Stripe
 *     call happens inside the transaction.
 *   - `releaseReservation` : compensation. Restores the reserved stock and
 *     moves the session to `failed` / `expired`. Idempotent - a second call
 *     (or an overlap with the Phase 8.13.4 sweep) is a safe no-op.
 *
 * Atomicity note: a Firestore transaction and a Stripe API call cannot be
 * one atomic unit. `createPaymentIntent` commits the reservation first, then
 * calls Stripe, and on a Stripe failure calls `releaseReservation` to
 * compensate. If compensation ALSO fails, the session is left `reserved`
 * with `expiresAt` set and the Phase 8.13.4 scheduled sweep is the backstop.
 */

export type ReserveOutcome =
  | {
      kind: "created";
      totals: OrderTotalsRupees;
      amountMinor: number;
      currency: string;
      expiresAtMs: number;
    }
  | {
      kind: "needs_payment_intent";
      totals: OrderTotalsRupees;
      amountMinor: number;
      currency: string;
      expiresAtMs: number;
    }
  | {
      kind: "has_payment_intent";
      paymentIntentId: string;
      totals: OrderTotalsRupees;
      amountMinor: number;
      currency: string;
      expiresAtMs: number;
    }
  | { kind: "foreign" }
  | { kind: "already_completed" }
  | { kind: "attempt_closed" }
  | { kind: "expired" };

function moneyOrZero(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function storedTotals(data: Record<string, unknown>): OrderTotalsRupees {
  return {
    subtotal: moneyOrZero(data.subtotal),
    deliveryFee: moneyOrZero(data.deliveryFee),
    discount: moneyOrZero(data.discount),
    total: moneyOrZero(data.total),
  };
}

export async function reserveOrClassify(args: {
  uid: string;
  sessionId: string;
  request: ParsedCreatePaymentIntentRequest;
  nowMs: number;
}): Promise<ReserveOutcome> {
  const { uid, sessionId, request, nowMs } = args;
  const database = db();
  const sessionRef = checkoutSessionDoc(sessionId);

  const aggregated = aggregateQuantitiesByProduct(request.items);
  const productIds = [...aggregated.keys()];

  try {
    return await database.runTransaction<ReserveOutcome>(async (tx) => {
      // ---- READS (all reads precede all writes) ----
      const sessionSnap = await tx.get(sessionRef);

      if (sessionSnap.exists) {
        const data = (sessionSnap.data() ?? {}) as Record<string, unknown>;
        const verdict = classifyExistingSession(data, uid, nowMs);
        switch (verdict.kind) {
          case "foreign":
            return { kind: "foreign" };
          case "already_completed":
            return { kind: "already_completed" };
          case "attempt_closed":
            return { kind: "attempt_closed" };
          case "expired":
            return { kind: "expired" };
          case "needs_payment_intent":
          case "has_payment_intent": {
            const totals = storedTotals(data);
            const amountMinor =
              typeof data.amountMinor === "number"
                ? data.amountMinor
                : toStripeMinorUnits(totals.total, ORDER_CURRENCY);
            const expiresAtMs =
              timestampToMillis(data.expiresAt) ?? nowMs + RESERVATION_TTL_MS;
            const currency =
              typeof data.currency === "string" ? data.currency : ORDER_CURRENCY;
            return verdict.kind === "has_payment_intent"
              ? {
                  kind: "has_payment_intent",
                  paymentIntentId: verdict.paymentIntentId,
                  totals,
                  amountMinor,
                  currency,
                  expiresAtMs,
                }
              : { kind: "needs_payment_intent", totals, amountMinor, currency, expiresAtMs };
          }
        }
      }

      // New reservation. Address read under the CALLER's own uid == ownership.
      const addrSnap = await tx.get(userAddressDoc(uid, request.addressId));
      if (!addrSnap.exists) {
        throw errAddressNotFound();
      }
      const pointerSnap = await tx.get(userAddressDefaultPointerDoc(uid));
      const defaultAddressId =
        pointerSnap.exists && typeof pointerSnap.data()?.defaultAddressId === "string"
          ? (pointerSnap.data()!.defaultAddressId as string)
          : null;

      const productSnaps = await tx.getAll(...productIds.map((id) => productDoc(id)));
      const productById = new Map<string, DocumentSnapshot>(
        productSnaps.map((snap) => [snap.id, snap]),
      );

      // ---- VALIDATE + PRICE ----
      const lineItems: CheckoutSessionLineItem[] = request.items.map((item) => {
        const snap = productById.get(item.productId);
        if (!snap || !snap.exists) {
          throw errProductUnavailable(item.productId);
        }
        const data = (snap.data() ?? {}) as Record<string, unknown>;
        assertProductPurchasable(item.productId, data);
        assertVariantAvailable(item.productId, data, item);
        const unitPriceRupees = productPriceRupees(data);
        const image = productMainImage(data);
        return {
          productId: item.productId,
          quantity: item.quantity,
          selectedColor: item.selectedColor,
          selectedSize: item.selectedSize,
          unitPriceRupees,
          lineTotalRupees: unitPriceRupees * item.quantity,
          productName: productTitle(data),
          imagePath: image.imagePath,
          imageSource: image.imageSource,
        };
      });

      const stockTargets = new Map<string, number>();
      for (const [productId, requestedQty] of aggregated) {
        const data = (productById.get(productId)!.data() ?? {}) as Record<string, unknown>;
        const available = productStockQuantity(data);
        const title = productTitle(data) || productId;
        if (available <= 0) {
          throw errOutOfStock(productId, title);
        }
        if (available < requestedQty) {
          throw errInsufficientStock(productId, title, available, requestedQty);
        }
        stockTargets.set(productId, available - requestedQty);
      }

      const totals = computeOrderTotals(
        lineItems.map((l) => ({
          productId: l.productId,
          quantity: l.quantity,
          unitPriceRupees: l.unitPriceRupees,
        })),
      );
      if (totals.total <= 0) {
        throw errOrderTotalInvalid();
      }
      const amountMinor = toStripeMinorUnits(totals.total, ORDER_CURRENCY);

      const deliveryAddressSnapshot = buildDeliveryAddressSnapshot(
        request.addressId,
        (addrSnap.data() ?? {}) as Record<string, unknown>,
        defaultAddressId,
      );

      // ---- WRITES ----
      const expiresAt = Timestamp.fromMillis(nowMs + RESERVATION_TTL_MS);
      const serverTimestamp = FieldValue.serverTimestamp();
      const sessionDocData = buildReservedSessionDoc({
        userId: uid,
        items: lineItems,
        totals,
        deliveryAddressSnapshot: deliveryAddressSnapshot as unknown as Record<string, unknown>,
        idempotencyKey: request.idempotencyKey,
        currency: ORDER_CURRENCY,
        amountMinor,
        expiresAt,
        serverTimestamp,
      });

      // `create` (not `set`): if the doc raced into existence the commit
      // fails and the transaction retries; on retry the `tx.get` above sees
      // it and classifies instead of blindly overwriting a live session.
      tx.create(sessionRef, sessionDocData);
      for (const [productId, target] of stockTargets) {
        tx.update(productDoc(productId), {
          stockQuantity: target,
          lastStockUpdatedAt: FieldValue.serverTimestamp(),
        });
      }

      return {
        kind: "created",
        totals,
        amountMinor,
        currency: ORDER_CURRENCY,
        expiresAtMs: expiresAt.toMillis(),
      };
    });
  } catch (err) {
    // A thrown HttpsError (validation / stock / address) propagates unchanged.
    if (err instanceof HttpsError) {
      throw err;
    }
    // ALREADY_EXISTS at commit despite the read-contention retry, or another
    // unexpected Firestore fault -> a clean "please retry", never a raw leak.
    logger.error("createPaymentIntent: reservation transaction failed", {
      sessionId,
      name: (err as { name?: unknown })?.name,
      code: (err as { code?: unknown })?.code,
      message: (err as { message?: unknown })?.message,
    });
    throw errReservationConflict();
  }
}

/**
 * Compensation: restore the stock a `reserved` session is holding and move
 * it to `newStatus` (`failed` after a Stripe error, `expired` for a
 * deadline). Idempotent: if the session is already non-`reserved` (a
 * concurrent sweep, a double call) it is a no-op.
 */
export async function releaseReservation(
  sessionId: string,
  newStatus: Extract<CheckoutSessionStatus, "failed" | "expired">,
): Promise<{ released: boolean; reason?: string }> {
  const database = db();
  const sessionRef = checkoutSessionDoc(sessionId);

  return database.runTransaction(async (tx) => {
    const sessionSnap = await tx.get(sessionRef);
    if (!sessionSnap.exists) {
      return { released: false, reason: "session_missing" };
    }
    const data = (sessionSnap.data() ?? {}) as Record<string, unknown>;
    if (data.status !== "reserved") {
      return { released: false, reason: `already_${String(data.status)}` };
    }

    const items = Array.isArray(data.items) ? (data.items as Record<string, unknown>[]) : [];
    const restoreByProduct = aggregateQuantitiesByProduct(
      items
        .map((it) => ({
          productId: typeof it.productId === "string" ? it.productId : "",
          quantity: typeof it.quantity === "number" ? it.quantity : 0,
        }))
        .filter((it) => it.productId.length > 0 && it.quantity > 0),
    );

    const productIds = [...restoreByProduct.keys()];
    const productSnaps =
      productIds.length > 0 ? await tx.getAll(...productIds.map((id) => productDoc(id))) : [];
    const productExists = new Map(productSnaps.map((s) => [s.id, s]));

    tx.update(sessionRef, {
      status: newStatus,
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const [productId, qty] of restoreByProduct) {
      const snap = productExists.get(productId);
      if (!snap || !snap.exists) {
        // Product deleted since reservation - its stock number is gone; nothing to restore.
        logger.warn("releaseReservation: product no longer exists, cannot restore stock", {
          sessionId,
          productId,
        });
        continue;
      }
      const current = productStockQuantity((snap.data() ?? {}) as Record<string, unknown>);
      tx.update(productDoc(productId), {
        stockQuantity: current + qty,
        lastStockUpdatedAt: FieldValue.serverTimestamp(),
      });
    }
    return { released: true };
  });
}
