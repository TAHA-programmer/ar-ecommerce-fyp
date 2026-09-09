import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

import { FUNCTIONS_REGION } from "./config";
import { applyCancelAdjustment, isCancelTransition } from "./lib/productStats";

/**
 * `adjustStatsOnOrderCancel` — Phase 9.3 "Dynamic Home Content" Stage 2.
 *
 * When an order transitions **to** `cancelled` (from any non-`cancelled`
 * status), decrement `productStats/{productId}.unitsSold` by that order's
 * purchased quantities. `cancelled` is terminal in the lifecycle graph, so
 * there is no re-increment case.
 *
 * Exactly idempotent: `applyCancelAdjustment` creates a
 * `statsAdjustments/{orderId}` ledger document in the same transaction as the
 * decrement, so a duplicate delivery of this trigger is a no-op. An
 * already-cancelled → cancelled write (should not happen, but harmless) is
 * filtered out here before the transaction. `retry: true` because the
 * transaction is safe to retry (the ledger makes it idempotent).
 */
export const adjustStatsOnOrderCancel = onDocumentUpdated(
  {
    region: FUNCTIONS_REGION,
    document: "orders/{orderId}",
    memory: "256MiB",
    retry: true,
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    if (!isCancelTransition(before.orderStatus, after.orderStatus)) return;

    const orderId = event.params.orderId as string;
    try {
      const outcome = await applyCancelAdjustment(orderId, after.items);
      logger.info("productStats: order-cancel adjustment", {
        orderId,
        outcome: outcome.kind,
      });
    } catch (err) {
      logger.error("productStats: order-cancel adjustment failed", { orderId, err });
      throw err; // retry — the statsAdjustments ledger keeps it idempotent
    }
  },
);
