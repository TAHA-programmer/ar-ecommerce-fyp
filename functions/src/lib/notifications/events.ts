import { LOW_STOCK_THRESHOLD } from "./constants";
import type { CustomerNotificationType } from "./types";

/**
 * Pure event classifiers: decide, from a Firestore `before`/`after` pair (or
 * a ledger outcome string), whether a notification-worthy event happened.
 * Stage S3 wires these into triggers; S1 only defines and tests them.
 */

type Doc = Record<string, unknown> | null | undefined;

function toInt(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : 0;
}

function isNum(value: unknown): boolean {
  return typeof value === "number" && Number.isFinite(value);
}

/** Epoch millis from a Firestore Timestamp-like (`toMillis()`), a
 *  `{seconds|_seconds, nanoseconds|_nanoseconds}` object, or a number.
 *  `null` when unreadable. */
export function timestampMillis(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value);
  if (value && typeof value === "object") {
    const v = value as Record<string, unknown>;
    if (typeof v.toMillis === "function") {
      const ms = (v.toMillis as () => unknown).call(value);
      return typeof ms === "number" && Number.isFinite(ms) ? Math.trunc(ms) : null;
    }
    const seconds = typeof v.seconds === "number" ? v.seconds : v._seconds;
    const nanos = typeof v.nanoseconds === "number" ? v.nanoseconds : v._nanoseconds;
    if (typeof seconds === "number" && Number.isFinite(seconds)) {
      const n = typeof nanos === "number" && Number.isFinite(nanos) ? nanos : 0;
      return Math.trunc(seconds * 1000 + n / 1e6);
    }
  }
  return null;
}

// ---------------------------------------------------------------- stock --

export type StockEventKind = "low_stock" | "out_of_stock";

/**
 * Stock alerts fire on a CROSSING that makes things worse, never on a level:
 *   - `> 0 -> 0`                        => out_of_stock
 *   - `> threshold -> 1..threshold`     => low_stock
 * Everything else (still-low decrements, restocks, no change, 0 -> low,
 * unreadable data) returns `null`. Reservations that drop a product
 * straight from above the band to 0 yield only out_of_stock.
 */
export function classifyStockChange(
  before: Doc,
  after: Doc,
  threshold: number = LOW_STOCK_THRESHOLD,
): StockEventKind | null {
  if (!before || !after) return null;
  // An unreadable quantity must never raise an alert (toInt would read it as
  // 0 and fake an out-of-stock), so both sides must be real numbers.
  if (!isNum(before.stockQuantity) || !isNum(after.stockQuantity)) return null;
  const b = toInt(before.stockQuantity);
  const a = toInt(after.stockQuantity);
  if (a === b) return null;
  if (a <= 0) return b > 0 ? "out_of_stock" : null;
  if (a <= threshold && b > threshold) return "low_stock";
  return null;
}

// ---------------------------------------------------------------- order --

const ORDER_STATUS_TO_TYPE: Readonly<
  Record<string, Extract<CustomerNotificationType, `order_${string}`>>
> = {
  confirmed: "order_confirmed",
  shipped: "order_shipped",
  delivered: "order_delivered",
  cancelled: "order_cancelled",
};

/** A customer-facing order status transition, or `null` (no change, move to
 *  `pending`, or an unknown/corrupt status). */
export function classifyOrderStatusChange(
  before: Doc,
  after: Doc,
): Extract<CustomerNotificationType, `order_${string}`> | null {
  if (!before || !after) return null;
  const from = before.orderStatus;
  const to = after.orderStatus;
  if (typeof to !== "string" || from === to) return null;
  return ORDER_STATUS_TO_TYPE[to] ?? null;
}

// --------------------------------------------------------------- review --

export type ReviewEvent =
  | { kind: "flagged" }
  | {
      kind: "moderated";
      type: Extract<CustomerNotificationType, "review_hidden" | "review_rejected" | "review_restored">;
      moderatedAtMs: number;
    };

/**
 * Review events from a `reviews/{id}` update.
 *
 * - `flagged`: `flaggedForReview` flipped false -> true (admin push).
 * - `moderated`: ONLY when an admin actually acted - `moderatedBy` is a
 *   non-empty string, `moderatedAt` is readable and CHANGED, and `status`
 *   changed. An author's own create/edit goes through `submitReview`, which
 *   resets `moderatedAt`/`moderatedBy` to null (`submitReview.ts`), so it can
 *   never be mistaken for moderation. A re-moderation that leaves `status`
 *   unchanged changes nothing for the author and is ignored.
 */
export function classifyReviewChange(before: Doc, after: Doc): ReviewEvent[] {
  if (!before || !after) return [];
  const events: ReviewEvent[] = [];

  if (before.flaggedForReview !== true && after.flaggedForReview === true) {
    events.push({ kind: "flagged" });
  }

  const by = after.moderatedBy;
  const atMs = timestampMillis(after.moderatedAt);
  const prevAtMs = timestampMillis(before.moderatedAt);
  if (
    typeof by === "string" &&
    by.length > 0 &&
    atMs !== null &&
    atMs > 0 &&
    atMs !== prevAtMs &&
    before.status !== after.status
  ) {
    if (after.status === "hidden") {
      events.push({ kind: "moderated", type: "review_hidden", moderatedAtMs: atMs });
    } else if (after.status === "rejected") {
      events.push({ kind: "moderated", type: "review_rejected", moderatedAtMs: atMs });
    } else if (after.status === "published") {
      events.push({ kind: "moderated", type: "review_restored", moderatedAtMs: atMs });
    }
  }
  return events;
}

// ---------------------------------------------------------- stripe event --

export type StripeLedgerEvent =
  | { kind: "refund"; sessionStatus: string }
  | { kind: "anomaly" };

const REFUND_PREFIX = "refunded_reservation_lost:";

/** Classify a `stripeEvents/{id}.outcome` string written by the existing
 *  finalize/sweep paths. Only the outcomes the plan names (C6/A5) map to an
 *  event; every other ledger outcome returns `null`. */
export function classifyStripeLedgerOutcome(outcome: unknown): StripeLedgerEvent | null {
  if (typeof outcome !== "string") return null;
  if (outcome.startsWith(REFUND_PREFIX)) {
    return { kind: "refund", sessionStatus: outcome.slice(REFUND_PREFIX.length) };
  }
  if (outcome === "inconsistent_order_payment") return { kind: "anomaly" };
  return null;
}
