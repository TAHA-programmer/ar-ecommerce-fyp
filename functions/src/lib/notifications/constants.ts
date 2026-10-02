/**
 * FCM notifications (`26_FCM_NOTIFICATIONS_PLAN.md`) - Stage S1 constants.
 *
 * Pure values only: no `firebase-functions/params` here. The
 * `NOTIFICATIONS_ENABLED` kill-switch param is declared in Stage S3 (when
 * triggers are wired) and passed into the pure library as a boolean.
 */

/** MUST equal the Flutter client's `CommerceDatabase.lowStockThreshold`
 *  (`lib/core/data/commerce_database.dart`). A drift test in
 *  `__tests__/constants.test.ts` reads that Dart file and fails if they
 *  differ. */
export const LOW_STOCK_THRESHOLD = 5;

/** Admin stock alerts: at most one per product per kind per window, so a
 *  checkout reserve -> fail -> restore cycle around the threshold can't spam. */
export const LOW_STOCK_COOLDOWN_MS = 6 * 60 * 60 * 1000;
export const OUT_OF_STOCK_COOLDOWN_MS = 6 * 60 * 60 * 1000;

const DAY_MS = 24 * 60 * 60 * 1000;
/** Customer inbox retention (Firestore TTL backstop on `expireAt`). */
export const INBOX_TTL_MS = 90 * DAY_MS;
/** Device-token retention; refreshed by the client's weekly re-register. */
export const DEVICE_TOKEN_TTL_MS = 60 * DAY_MS;
/** Admin idempotency/cooldown ledger retention. */
export const LEDGER_TTL_MS = 7 * DAY_MS;

/** Per-user registered-device cap (oldest `lastSeenAt` evicted). */
export const MAX_DEVICES_PER_USER = 10;

/** FCM message time-to-live: a stale "shipped" push is worse than none. */
export const FCM_MESSAGE_TTL_MS = 24 * 60 * 60 * 1000;

/** `sendEachForMulticast` hard limit. */
export const FCM_MAX_TOKENS_PER_BATCH = 500;

/** Defence against a bug-driven loop: max pushes per recipient per window. */
export const RECIPIENT_PUSH_CAP = 10;
export const RECIPIENT_PUSH_WINDOW_MS = 10 * 60 * 1000;

/** Data-payload schema version understood by the app's NotificationRouter. */
export const PAYLOAD_VERSION = "1";

/** Android channel ids - created natively by the app (plan §4.5). */
export const CHANNEL_ORDERS = "orders";
export const CHANNEL_ACCOUNT = "account";
export const CHANNEL_ADMIN_OPS = "admin_ops";
export const CHANNEL_ADMIN_STOCK = "admin_stock";

/** Firestore collection names (new in this feature). */
export const DEVICE_TOKENS_COLLECTION = "deviceTokens";
export const NOTIFICATION_EVENTS_COLLECTION = "notificationEvents";
export const NOTIFICATIONS_SUBCOLLECTION = "notifications";
export const NOTIFICATION_SETTINGS_SUBCOLLECTION = "notificationSettings";
export const NOTIFICATION_PREFS_DOC_ID = "prefs";
