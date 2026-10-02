import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

import { FUNCTIONS_REGION, notificationsEnabled } from "./config";
import {
  defaultNotifyDeps,
  handleOrderCreated,
  handleOrderStatusChange,
  handleProductStockChange,
  handleReviewChange,
  handleStripeEventCreated,
} from "./lib/notifications/triggers";

/**
 * FCM notification triggers (`26_FCM_NOTIFICATIONS_PLAN.md` §4.9). Each is a
 * thin wrapper: all logic lives in `lib/notifications/triggers.ts`. All are
 * gated by the `NOTIFICATIONS_ENABLED` kill-switch (default OFF) inside the
 * handlers. `retry: true` is safe because every side effect is idempotent
 * (deterministic inbox ids / the admin ledger); a failed PUSH never throws.
 */

const BASE = { region: FUNCTIONS_REGION, memory: "256MiB", retry: true } as const;

function fail(name: string, id: string, err: unknown): never {
  logger.error(`${name}: failed`, { id, name: (err as { name?: unknown })?.name });
  throw err; // retry - the ledger / deterministic ids keep it idempotent
}

export const onOrderCreatedNotify = onDocumentCreated(
  { ...BASE, document: "orders/{orderId}" },
  async (event) => {
    const orderId = event.params.orderId as string;
    try {
      await handleOrderCreated(
        orderId,
        event.data?.data(),
        defaultNotifyDeps(notificationsEnabled.value()),
      );
    } catch (err) {
      fail("onOrderCreatedNotify", orderId, err);
    }
  },
);

export const onOrderStatusNotify = onDocumentUpdated(
  { ...BASE, document: "orders/{orderId}" },
  async (event) => {
    const orderId = event.params.orderId as string;
    try {
      await handleOrderStatusChange(
        orderId,
        event.data?.before?.data(),
        event.data?.after?.data(),
        defaultNotifyDeps(notificationsEnabled.value()),
      );
    } catch (err) {
      fail("onOrderStatusNotify", orderId, err);
    }
  },
);

export const onProductStockNotify = onDocumentUpdated(
  { ...BASE, document: "products/{productId}" },
  async (event) => {
    const productId = event.params.productId as string;
    try {
      await handleProductStockChange(
        productId,
        event.data?.before?.data(),
        event.data?.after?.data(),
        defaultNotifyDeps(notificationsEnabled.value()),
      );
    } catch (err) {
      fail("onProductStockNotify", productId, err);
    }
  },
);

export const onReviewNotify = onDocumentUpdated(
  { ...BASE, document: "reviews/{reviewId}" },
  async (event) => {
    const reviewId = event.params.reviewId as string;
    try {
      await handleReviewChange(
        reviewId,
        event.data?.before?.data(),
        event.data?.after?.data(),
        defaultNotifyDeps(notificationsEnabled.value()),
      );
    } catch (err) {
      fail("onReviewNotify", reviewId, err);
    }
  },
);

export const onStripeEventNotify = onDocumentCreated(
  { ...BASE, document: "stripeEvents/{eventId}" },
  async (event) => {
    const eventId = event.params.eventId as string;
    try {
      await handleStripeEventCreated(
        eventId,
        event.data?.data(),
        defaultNotifyDeps(notificationsEnabled.value()),
      );
    } catch (err) {
      fail("onStripeEventNotify", eventId, err);
    }
  },
);
