import {
  CHANNEL_ACCOUNT,
  CHANNEL_ADMIN_OPS,
  CHANNEL_ADMIN_STOCK,
  CHANNEL_ORDERS,
} from "./constants";
import type {
  CatalogEntry,
  NotificationParams,
  NotificationType,
  RenderedNotification,
} from "./types";

/**
 * Notification catalogue: type -> channel / route / priority / copy.
 * Pure. Copy rules (plan §4.11): lock-screen safe - order short-id + status
 * only; no address, items, amounts, moderation reason or reporter identity;
 * a cancellation never promises a refund (deferred no-restock semantics).
 */
export const CATALOG: Readonly<Record<NotificationType, CatalogEntry>> = {
  order_placed: {
    audience: "customer",
    category: "orders",
    channelId: CHANNEL_ORDERS,
    route: "orderDetail",
    androidPriority: "high",
    pushes: false,
    inbox: true,
  },
  order_confirmed: {
    audience: "customer",
    category: "orders",
    channelId: CHANNEL_ORDERS,
    route: "orderDetail",
    androidPriority: "high",
    pushes: true,
    inbox: true,
  },
  order_shipped: {
    audience: "customer",
    category: "orders",
    channelId: CHANNEL_ORDERS,
    route: "orderDetail",
    androidPriority: "high",
    pushes: true,
    inbox: true,
  },
  order_delivered: {
    audience: "customer",
    category: "orders",
    channelId: CHANNEL_ORDERS,
    route: "orderDetail",
    androidPriority: "high",
    pushes: true,
    inbox: true,
  },
  order_cancelled: {
    audience: "customer",
    category: "orders",
    channelId: CHANNEL_ORDERS,
    route: "orderDetail",
    androidPriority: "high",
    pushes: true,
    inbox: true,
  },
  payment_refunded: {
    audience: "customer",
    category: "orders",
    channelId: CHANNEL_ORDERS,
    route: "orders",
    androidPriority: "high",
    pushes: true,
    inbox: true,
  },
  review_hidden: {
    audience: "customer",
    category: "reviews",
    channelId: CHANNEL_ACCOUNT,
    route: "myReviews",
    androidPriority: "normal",
    pushes: true,
    inbox: true,
  },
  review_rejected: {
    audience: "customer",
    category: "reviews",
    channelId: CHANNEL_ACCOUNT,
    route: "myReviews",
    androidPriority: "normal",
    pushes: true,
    inbox: true,
  },
  review_restored: {
    audience: "customer",
    category: "reviews",
    channelId: CHANNEL_ACCOUNT,
    route: "myReviews",
    androidPriority: "normal",
    pushes: false,
    inbox: true,
  },
  admin_new_order: {
    audience: "admin",
    category: "adminOrders",
    channelId: CHANNEL_ADMIN_OPS,
    route: "adminOrderDetail",
    androidPriority: "high",
    pushes: true,
    inbox: false,
  },
  admin_low_stock: {
    audience: "admin",
    category: "adminStock",
    channelId: CHANNEL_ADMIN_STOCK,
    route: "adminInventory",
    androidPriority: "normal",
    pushes: true,
    inbox: false,
  },
  admin_out_of_stock: {
    audience: "admin",
    category: "adminStock",
    channelId: CHANNEL_ADMIN_STOCK,
    route: "adminInventory",
    androidPriority: "normal",
    pushes: true,
    inbox: false,
  },
  admin_review_flagged: {
    audience: "admin",
    category: "adminModeration",
    channelId: CHANNEL_ADMIN_STOCK,
    route: "adminReviews",
    androidPriority: "normal",
    pushes: true,
    inbox: false,
  },
  admin_payment_issue: {
    audience: "admin",
    category: "adminPayments",
    channelId: CHANNEL_ADMIN_OPS,
    route: "adminNotifications",
    androidPriority: "high",
    pushes: true,
    inbox: false,
  },
};

const WEBHOOK_ORDER_SHAPE = /^ord_([0-9a-f]{16,64})$/;
const MAX_TITLE_FRAGMENT = 60;

/** Server mirror of the Flutter `OrderIdFormatter.short` for webhook ids:
 *  `ord_<hex>` -> `#<first 8 hex, upper>`. Any other id is bounded so copy
 *  never carries a 44-character raw id. */
export function shortOrderId(orderId: string): string {
  const m = WEBHOOK_ORDER_SHAPE.exec(orderId);
  if (m) return `#${m[1].slice(0, 8).toUpperCase()}`;
  const trimmed = orderId.trim();
  const withHash = trimmed.startsWith("#") ? trimmed : `#${trimmed}`;
  return withHash.length > 12 ? withHash.slice(0, 12) : withHash;
}

/** Product titles are admin-authored free text: collapse whitespace/control
 *  characters and bound the length before they enter a notification body. */
export function sanitizeFragment(value: string | undefined, fallback: string): string {
  const cleaned = (value ?? "")
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001f\u007f]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!cleaned) return fallback;
  return cleaned.length > MAX_TITLE_FRAGMENT
    ? `${cleaned.slice(0, MAX_TITLE_FRAGMENT - 1)}…`
    : cleaned;
}

export class NotificationCatalogError extends Error {}

function need(value: string | undefined, name: string, type: NotificationType): string {
  if (!value) {
    throw new NotificationCatalogError(`${type} requires ${name}`);
  }
  return value;
}

/** Render title/body/tag/entity for a notification. Throws
 *  [NotificationCatalogError] when a required entity id is missing (a
 *  programming error, never user input). */
export function renderNotification(
  type: NotificationType,
  params: NotificationParams = {},
): RenderedNotification {
  const entry = CATALOG[type];
  let title: string;
  let body: string;
  let entityId: string | null = null;
  let tag: string;

  switch (type) {
    case "order_placed": {
      const id = need(params.orderId, "orderId", type);
      entityId = id;
      tag = id;
      title = "Order placed";
      body = `Your order ${shortOrderId(id)} has been placed. We'll update you as it progresses.`;
      break;
    }
    case "order_confirmed": {
      const id = need(params.orderId, "orderId", type);
      entityId = id;
      tag = id;
      title = "Order confirmed";
      body = `Order ${shortOrderId(id)} has been confirmed and is being prepared.`;
      break;
    }
    case "order_shipped": {
      const id = need(params.orderId, "orderId", type);
      entityId = id;
      tag = id;
      title = "Order shipped";
      body = `Order ${shortOrderId(id)} is on its way.`;
      break;
    }
    case "order_delivered": {
      const id = need(params.orderId, "orderId", type);
      entityId = id;
      tag = id;
      title = "Order delivered";
      body = `Order ${shortOrderId(id)} has been delivered. Tap to view it or rate your items.`;
      break;
    }
    case "order_cancelled": {
      const id = need(params.orderId, "orderId", type);
      entityId = id;
      tag = id;
      title = "Order cancelled";
      body = `Order ${shortOrderId(id)} was cancelled. Contact support if you have questions.`;
      break;
    }
    case "payment_refunded":
      tag = "payment_refunded";
      title = "Payment refunded";
      body = "Your payment couldn't be turned into an order in time, so a refund was issued.";
      break;
    case "review_hidden": {
      const id = need(params.reviewId, "reviewId", type);
      entityId = id;
      tag = `review_${id}`;
      title = "Review hidden";
      body = "Your review was hidden by our moderation team. You can see it in My Reviews.";
      break;
    }
    case "review_rejected": {
      const id = need(params.reviewId, "reviewId", type);
      entityId = id;
      tag = `review_${id}`;
      title = "Review not published";
      body = "Your review didn't meet our guidelines and wasn't published. See My Reviews.";
      break;
    }
    case "review_restored": {
      const id = need(params.reviewId, "reviewId", type);
      entityId = id;
      tag = `review_${id}`;
      title = "Review restored";
      body = "Your review is visible again.";
      break;
    }
    case "admin_new_order": {
      const id = need(params.orderId, "orderId", type);
      entityId = id;
      tag = `admin_order_${id}`;
      title = "New order";
      body = `Order ${shortOrderId(id)} is awaiting confirmation.`;
      break;
    }
    case "admin_low_stock": {
      const id = need(params.productId, "productId", type);
      entityId = id;
      tag = `admin_stock_${id}`;
      const qty = Math.max(0, Math.trunc(params.stockQuantity ?? 0));
      title = "Low stock";
      body = `${sanitizeFragment(params.productTitle, "A product")}: ${qty} left.`;
      break;
    }
    case "admin_out_of_stock": {
      const id = need(params.productId, "productId", type);
      entityId = id;
      tag = `admin_stock_${id}`;
      title = "Out of stock";
      body = `${sanitizeFragment(params.productTitle, "A product")} is out of stock.`;
      break;
    }
    case "admin_review_flagged": {
      const id = need(params.reviewId, "reviewId", type);
      entityId = id;
      tag = `admin_flag_${id}`;
      title = "Review flagged";
      body = "A review has been reported several times and needs moderation.";
      break;
    }
    case "admin_payment_issue":
      tag = "admin_payment_issue";
      title = "Payment issue";
      body = "A payment needs attention. Check Orders.";
      break;
  }

  return {
    type,
    audience: entry.audience,
    category: entry.category,
    channelId: entry.channelId,
    route: entry.route,
    androidPriority: entry.androidPriority,
    pushes: entry.pushes,
    inbox: entry.inbox,
    title,
    body,
    tag,
    entityId,
  };
}
