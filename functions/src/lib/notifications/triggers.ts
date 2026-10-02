import * as logger from "firebase-functions/logger";
import { getAuth } from "firebase-admin/auth";
import { getMessaging } from "firebase-admin/messaging";

import { checkoutSessionDoc } from "../firestore";
import { LOW_STOCK_COOLDOWN_MS, OUT_OF_STOCK_COOLDOWN_MS } from "./constants";
import { adminKeys, customerOrderKey, refundKey, reviewModerationKey } from "./dedupe";
import {
  classifyOrderStatusChange,
  classifyReviewChange,
  classifyStockChange,
  classifyStripeLedgerOutcome,
} from "./events";
import { notifyAdmins, notifyCustomer, type NotifyDeps, type NotifyResult } from "./notify";

/**
 * Pure-ish trigger handlers: each takes the already-extracted Firestore
 * documents and an injected `NotifyDeps`, so the emulator tests drive the
 * REAL logic with a fake FCM. The deployed wrappers (`src/notify*.ts`) only
 * extract event data and build `defaultNotifyDeps`.
 */

type Doc = Record<string, unknown> | null | undefined;

/** Production dependencies. `enabled` is read from the
 *  `NOTIFICATIONS_ENABLED` param by the wrapper (params are only readable at
 *  runtime inside a function, never at import time). */
export function defaultNotifyDeps(enabled: boolean): NotifyDeps {
  return {
    enabled,
    messaging: getMessaging(),
    nowMs: Date.now(),
    verifyAdmin: async (uid: string) => {
      const user = await getAuth().getUser(uid);
      return user.customClaims?.role === "superAdmin";
    },
  };
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

/** `orders/{id}` created -> admin "new order" + customer inbox-only receipt. */
export async function handleOrderCreated(
  orderId: string,
  order: Doc,
  deps: NotifyDeps,
): Promise<NotifyResult[]> {
  if (!order) return [];
  const results: NotifyResult[] = [];
  results.push(
    await notifyAdmins(
      {
        type: "admin_new_order",
        params: { orderId },
        dedupeKey: adminKeys.newOrder(orderId),
        cooldownMs: null,
      },
      deps,
    ),
  );
  const uid = str(order.userId);
  if (uid) {
    results.push(
      await notifyCustomer(
        {
          uid,
          type: "order_placed",
          params: { orderId },
          dedupeKey: customerOrderKey("order_placed", orderId),
        },
        deps,
      ),
    );
  }
  return results;
}

/** `orders/{id}` updated -> customer status notification (admin never
 *  notified of their own action). */
export async function handleOrderStatusChange(
  orderId: string,
  before: Doc,
  after: Doc,
  deps: NotifyDeps,
): Promise<NotifyResult[]> {
  const type = classifyOrderStatusChange(before, after);
  const uid = str(after?.userId);
  if (!type || !uid) return [];
  return [
    await notifyCustomer(
      {
        uid,
        type,
        params: { orderId },
        dedupeKey: customerOrderKey(type, orderId),
      },
      deps,
    ),
  ];
}

/** `products/{id}` updated -> admin low / out-of-stock (crossing + cooldown). */
export async function handleProductStockChange(
  productId: string,
  before: Doc,
  after: Doc,
  deps: NotifyDeps,
): Promise<NotifyResult[]> {
  const kind = classifyStockChange(before, after);
  if (!kind || !after) return [];
  const params = {
    productId,
    productTitle: typeof after.title === "string" ? after.title : undefined,
    stockQuantity: typeof after.stockQuantity === "number" ? after.stockQuantity : 0,
  };
  if (kind === "out_of_stock") {
    return [
      await notifyAdmins(
        {
          type: "admin_out_of_stock",
          params,
          dedupeKey: adminKeys.outOfStock(productId),
          cooldownMs: OUT_OF_STOCK_COOLDOWN_MS,
        },
        deps,
      ),
    ];
  }
  return [
    await notifyAdmins(
      {
        type: "admin_low_stock",
        params,
        dedupeKey: adminKeys.lowStock(productId),
        cooldownMs: LOW_STOCK_COOLDOWN_MS,
      },
      deps,
    ),
  ];
}

/** `reviews/{id}` updated -> admin "flagged" and/or customer moderation notice. */
export async function handleReviewChange(
  reviewId: string,
  before: Doc,
  after: Doc,
  deps: NotifyDeps,
): Promise<NotifyResult[]> {
  const results: NotifyResult[] = [];
  for (const event of classifyReviewChange(before, after)) {
    if (event.kind === "flagged") {
      results.push(
        await notifyAdmins(
          {
            type: "admin_review_flagged",
            params: { reviewId },
            dedupeKey: adminKeys.reviewFlagged(reviewId),
            cooldownMs: null,
          },
          deps,
        ),
      );
      continue;
    }
    const uid = str(after?.userId);
    if (!uid) continue;
    results.push(
      await notifyCustomer(
        {
          uid,
          type: event.type,
          params: { reviewId },
          dedupeKey: reviewModerationKey(event.type, reviewId, event.moderatedAtMs),
        },
        deps,
      ),
    );
  }
  return results;
}

/** `stripeEvents/{id}` created -> refund notice (customer) + payment issue
 *  (admin) for the two outcomes the plan names. */
export async function handleStripeEventCreated(
  eventId: string,
  record: Doc,
  deps: NotifyDeps,
): Promise<NotifyResult[]> {
  const event = classifyStripeLedgerOutcome(record?.outcome);
  if (!event || !record) return [];
  const results: NotifyResult[] = [];

  results.push(
    await notifyAdmins(
      {
        type: "admin_payment_issue",
        params: {},
        dedupeKey: adminKeys.anomaly(eventId),
        cooldownMs: null,
      },
      deps,
    ),
  );

  if (event.kind === "refund") {
    const paymentIntentId = str(record.paymentIntentId);
    const sessionId = str(record.checkoutSessionId);
    if (!paymentIntentId || !sessionId) {
      logger.warn("notifications: refund event without payment/session id - customer notice skipped");
      return results;
    }
    // The ledger record carries no uid; resolve the owner from the session.
    const session = await checkoutSessionDoc(sessionId).get();
    const uid = session.exists ? str((session.data() as Record<string, unknown>).userId) : null;
    if (!uid) {
      logger.warn("notifications: refund event session/owner not found - customer notice skipped");
      return results;
    }
    results.push(
      await notifyCustomer(
        {
          uid,
          type: "payment_refunded",
          params: {},
          dedupeKey: refundKey(paymentIntentId),
        },
        deps,
      ),
    );
  }
  return results;
}
