import { FieldValue, type DocumentSnapshot, type Transaction } from "firebase-admin/firestore";

import { aggregateQuantitiesByProduct } from "./aggregate";
import {
  db,
  favoriteVoterDoc,
  productStatsDoc,
  statsAdjustmentDoc,
  userFavoriteDoc,
} from "./firestore";

/**
 * Phase 9.3 "Dynamic Home Content" Stage 2 — server-maintained Home ordering
 * aggregates (`productStats/{productId}`).
 *
 * Three write paths, all EXACTLY idempotent under Cloud Functions retries:
 *
 *  1. `applyUnitsSoldOnFinalize` — bumps `unitsSold` for each purchased
 *     product. Runs INSIDE `finalizeSucceededPayment`'s existing transaction,
 *     in the `if (!orderSnap.exists)` block, so it is already guarded
 *     exactly-once by the `stripeEvents` ledger + the deterministic order id.
 *     `FieldValue.increment` is atomic and exact.
 *
 *  2. `applyCancelAdjustment` — decrements `unitsSold` when an order
 *     transitions to `cancelled`. Its own transaction, guarded by a
 *     `statsAdjustments/{orderId}` ledger document created in the SAME
 *     transaction as the decrement — a duplicate trigger delivery finds the
 *     ledger doc and is an exact no-op. Read-modify-write with a `>= 0`
 *     floor (never trusts a transform when exactness is the requirement).
 *
 *  3. `applyFavoriteChange` — reconciles `favoriteCount` against the
 *     AUTHORITATIVE `users/{uid}/favorites/{productId}` document, NOT against
 *     the trigger event payload. Its own transaction reads that favourite doc
 *     plus the per-(user,product) `productStats/{productId}/favoriteVoters/{uid}`
 *     guard: the guard doc exists iff this (user,product) is currently counted
 *     in `favoriteCount`. If "favourite exists" and "is counted" disagree, it
 *     makes them agree (+1 & create guard, or -1 & delete guard); if they
 *     already agree it is an exact no-op. Because every delivery re-derives
 *     from current truth, duplicate / out-of-order / stale-retried events all
 *     converge — `favoriteCount` ends equal to the number of live favourite
 *     docs, never drifting on a reversed create/delete pair.
 */

// ---------------------------------------------------------------------------

function numOr0(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

/** `true` only for a genuine "some other status → cancelled" transition. */
export function isCancelTransition(
  beforeStatus: unknown,
  afterStatus: unknown,
): boolean {
  return beforeStatus !== "cancelled" && afterStatus === "cancelled";
}

/** Maps a favourites document write to a count change, or `null` for a
 *  no-op (update, or before/after both present/absent). */
export function favoriteChangeKind(
  beforeExists: boolean,
  afterExists: boolean,
): FavoriteChangeKind | null {
  if (beforeExists === afterExists) return null;
  return afterExists ? "added" : "removed";
}

/** `{ productId -> total quantity }` from an order/session `items[]` array. */
export function soldQuantitiesFromItems(items: unknown): Map<string, number> {
  if (!Array.isArray(items)) return new Map();
  return aggregateQuantitiesByProduct(
    items
      .map((raw) => {
        const it = (raw ?? {}) as Record<string, unknown>;
        return {
          productId: typeof it.productId === "string" ? it.productId : "",
          quantity: typeof it.quantity === "number" ? it.quantity : 0,
        };
      })
      .filter((it) => it.productId.length > 0 && it.quantity > 0),
  );
}

// ---------------------------------------------------------------------------
// 1. unitsSold += qty  (inside the caller's finalize transaction)
// ---------------------------------------------------------------------------

export function applyUnitsSoldOnFinalize(
  tx: Transaction,
  soldMap: Map<string, number>,
  serverTimestamp: unknown,
): void {
  for (const [productId, qty] of soldMap) {
    if (qty <= 0) continue;
    tx.set(
      productStatsDoc(productId),
      {
        unitsSold: FieldValue.increment(qty),
        lastSoldAt: serverTimestamp,
        updatedAt: serverTimestamp,
      },
      { merge: true },
    );
  }
}

// ---------------------------------------------------------------------------
// 2. unitsSold -= qty on cancellation  (own transaction + ledger guard)
// ---------------------------------------------------------------------------

export type CancelAdjustmentOutcome =
  | { kind: "noop_no_items" }
  | { kind: "already_applied" }
  | { kind: "applied"; productIds: string[] };

export async function applyCancelAdjustment(
  orderId: string,
  orderItems: unknown,
): Promise<CancelAdjustmentOutcome> {
  const soldMap = soldQuantitiesFromItems(orderItems);
  if (soldMap.size === 0) return { kind: "noop_no_items" };

  return db().runTransaction<CancelAdjustmentOutcome>(async (tx) => {
    const ledgerRef = statsAdjustmentDoc(orderId);
    const ledgerSnap = await tx.get(ledgerRef);
    if (ledgerSnap.exists) return { kind: "already_applied" };

    const productIds = [...soldMap.keys()];
    const statsSnaps: DocumentSnapshot[] = await tx.getAll(
      ...productIds.map((id) => productStatsDoc(id)),
    );

    for (const snap of statsSnaps) {
      const qty = soldMap.get(snap.id) ?? 0;
      const next = Math.max(0, numOr0(snap.get("unitsSold")) - qty);
      tx.set(
        productStatsDoc(snap.id),
        { unitsSold: next, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
    tx.create(ledgerRef, {
      kind: "order_cancelled",
      orderId,
      appliedAt: FieldValue.serverTimestamp(),
    });
    return { kind: "applied", productIds };
  });
}

// ---------------------------------------------------------------------------
// 3. favoriteCount +/- 1  (own transaction + per-(user,product) voter guard)
// ---------------------------------------------------------------------------

export type FavoriteChangeKind = "added" | "removed";

export type FavoriteChangeOutcome =
  | { kind: "noop_bad_args" }
  | { kind: "already_counted" }
  | { kind: "already_removed" }
  | { kind: "incremented"; newCount: number }
  | { kind: "decremented"; newCount: number };

/**
 * Reconcile `productStats/{productId}.favoriteCount` for a single
 * (user, product) pair against the AUTHORITATIVE
 * `users/{uid}/favorites/{productId}` document. Safe to call for any
 * favourites write event — create, delete, duplicate, out-of-order or a
 * stale retry — because it reads current truth inside the transaction rather
 * than trusting the event.
 */
export async function applyFavoriteChange(args: {
  productId: string;
  uid: string;
}): Promise<FavoriteChangeOutcome> {
  const { productId, uid } = args;
  if (!productId || !uid) return { kind: "noop_bad_args" };

  return db().runTransaction<FavoriteChangeOutcome>(async (tx) => {
    const favoriteRef = userFavoriteDoc(uid, productId);
    const voterRef = favoriteVoterDoc(productId, uid);
    const statsRef = productStatsDoc(productId);
    // All reads before any write (Firestore transaction rule). The favourite
    // doc read also enrolls it in the transaction's read set, so a concurrent
    // favourite/unfavourite aborts+retries this transaction against the new
    // state instead of committing a stale decision.
    const [favoriteSnap, voterSnap, statsSnap] = await Promise.all([
      tx.get(favoriteRef),
      tx.get(voterRef),
      tx.get(statsRef),
    ]);

    const shouldBeCounted = favoriteSnap.exists;
    const isCounted = voterSnap.exists;
    if (shouldBeCounted === isCounted) {
      return { kind: isCounted ? "already_counted" : "already_removed" };
    }

    const current = numOr0(statsSnap.get("favoriteCount"));
    if (shouldBeCounted) {
      const next = current + 1;
      tx.set(
        statsRef,
        { favoriteCount: next, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      tx.create(voterRef, { at: FieldValue.serverTimestamp() });
      return { kind: "incremented", newCount: next };
    }

    const next = Math.max(0, current - 1);
    tx.set(
      statsRef,
      { favoriteCount: next, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    tx.delete(voterRef);
    return { kind: "decremented", newCount: next };
  });
}
