import {
  CHANNEL_ACCOUNT,
  CHANNEL_ADMIN_OPS,
  CHANNEL_ADMIN_STOCK,
  CHANNEL_ORDERS,
} from "./constants";

export const CUSTOMER_NOTIFICATION_TYPES = [
  "order_placed",
  "order_confirmed",
  "order_shipped",
  "order_delivered",
  "order_cancelled",
  "payment_refunded",
  "review_hidden",
  "review_rejected",
  "review_restored",
] as const;

export const ADMIN_NOTIFICATION_TYPES = [
  "admin_new_order",
  "admin_low_stock",
  "admin_out_of_stock",
  "admin_review_flagged",
  "admin_payment_issue",
] as const;

export type CustomerNotificationType = (typeof CUSTOMER_NOTIFICATION_TYPES)[number];
export type AdminNotificationType = (typeof ADMIN_NOTIFICATION_TYPES)[number];
export type NotificationType = CustomerNotificationType | AdminNotificationType;

export type Audience = "customer" | "admin";

/** The user-facing preference switch that gates a push (D7: every one is
 *  user-disableable; the customer inbox is never gated). */
export type PushCategory =
  | "orders"
  | "reviews"
  | "adminOrders"
  | "adminStock"
  | "adminModeration"
  | "adminPayments";

/** Destination enum stored on the inbox row. NEVER a path or URL - the app
 *  maps it (and the payload `type`) to a hard-coded route. */
export type ClientRoute =
  | "orderDetail"
  | "orders"
  | "myReviews"
  | "adminOrderDetail"
  | "adminInventory"
  | "adminReviews"
  | "adminNotifications";

export type ChannelId =
  | typeof CHANNEL_ORDERS
  | typeof CHANNEL_ACCOUNT
  | typeof CHANNEL_ADMIN_OPS
  | typeof CHANNEL_ADMIN_STOCK;

export type AndroidPriority = "high" | "normal";

/** Entity references a notification can carry. Strings only. */
export interface NotificationParams {
  orderId?: string;
  reviewId?: string;
  productId?: string;
  productTitle?: string;
  stockQuantity?: number;
}

export interface CatalogEntry {
  audience: Audience;
  category: PushCategory;
  channelId: ChannelId;
  route: ClientRoute;
  androidPriority: AndroidPriority;
  /** Whether a system push is ever attempted for this type. */
  pushes: boolean;
  /** Whether a persisted inbox row is written (customer only; admin has no
   *  inbox - plan §4.2). */
  inbox: boolean;
}

export interface RenderedNotification {
  type: NotificationType;
  audience: Audience;
  category: PushCategory;
  channelId: ChannelId;
  route: ClientRoute;
  androidPriority: AndroidPriority;
  pushes: boolean;
  inbox: boolean;
  title: string;
  body: string;
  /** Android notification `tag`: a later push with the same tag REPLACES
   *  the earlier tray entry (e.g. one entry per order). */
  tag: string;
  /** Entity id surfaced in the data payload and inbox `entityId`. */
  entityId: string | null;
}
