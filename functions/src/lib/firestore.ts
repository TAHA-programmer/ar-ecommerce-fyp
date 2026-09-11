import { getFirestore } from "firebase-admin/firestore";

import { CHECKOUT_SESSIONS_COLLECTION } from "./checkoutSession";

/**
 * Admin-SDK Firestore accessors for the checkout functions.
 *
 * Every call is lazy - it assumes `initializeApp()` has already run in
 * `index.ts` (which every deployed function transitively imports).
 *
 * Collection / document paths are centralised here so a path typo can't
 * silently read or write the wrong location. The Admin SDK bypasses
 * `firestore.rules` entirely, which is exactly why `createPaymentIntent`
 * re-checks product publication/active/stock and reads the address strictly
 * under the *caller's own* `users/{uid}/` path (that read IS the ownership
 * check).
 */

export const COLLECTIONS = {
  products: "products",
  orders: "orders",
  payments: "payments",
  checkoutSessions: CHECKOUT_SESSIONS_COLLECTION,
  stripeEvents: "stripeEvents",
  // Phase 9.3 "Dynamic Home Content" Stage 2.
  productStats: "productStats",
  statsAdjustments: "statsAdjustments",
  // Phase 9.3 "Virtual Try-On" Stage 4.
  tryOnSessions: "tryOnSessions",
  tryOnQuota: "tryOnQuota",
} as const;

/** The single server-owned document id used for the D9 global daily cap. */
export const TRY_ON_GLOBAL_QUOTA_DOC_ID = "_global";

/** The private per-(user,product) idempotency-guard subcollection under a
 *  `productStats/{productId}` document. Server-internal; `firestore.rules`
 *  denies all client access. */
export const FAVORITE_VOTERS_SUBCOLLECTION = "favoriteVoters";

export function db() {
  return getFirestore();
}

export function checkoutSessionsRef() {
  return db().collection(COLLECTIONS.checkoutSessions);
}

export function checkoutSessionDoc(sessionId: string) {
  return checkoutSessionsRef().doc(sessionId);
}

export function productsRef() {
  return db().collection(COLLECTIONS.products);
}

export function productDoc(productId: string) {
  return productsRef().doc(productId);
}

export function orderDoc(orderId: string) {
  return db().collection(COLLECTIONS.orders).doc(orderId);
}

export function paymentDoc(paymentId: string) {
  return db().collection(COLLECTIONS.payments).doc(paymentId);
}

/** `stripeEvents/{eventId}` - the server-only webhook idempotency ledger. */
export function stripeEventDoc(eventId: string) {
  return db().collection(COLLECTIONS.stripeEvents).doc(eventId);
}

/** `productStats/{productId}` - server-maintained Home ordering aggregate. */
export function productStatsDoc(productId: string) {
  return db().collection(COLLECTIONS.productStats).doc(productId);
}

/** `productStats/{productId}/favoriteVoters/{uid}` - the per-(user,product)
 *  idempotency guard for the favourite-count trigger. */
export function favoriteVoterDoc(productId: string, uid: string) {
  return productStatsDoc(productId).collection(FAVORITE_VOTERS_SUBCOLLECTION).doc(uid);
}

/** `users/{uid}/favorites/{productId}` - the AUTHORITATIVE favourite record
 *  (doc ID IS the productId). `adjustFavoriteCount` reconciles `favoriteCount`
 *  against the live existence of this document, never against the (possibly
 *  stale / out-of-order / duplicated) trigger event payload. */
export function userFavoriteDoc(uid: string, productId: string) {
  return db().doc(`users/${uid}/favorites/${productId}`);
}

/** `statsAdjustments/{orderId}` - server-only ledger: this order's
 *  cancellation has already been applied to `productStats`. */
export function statsAdjustmentDoc(orderId: string) {
  return db().collection(COLLECTIONS.statsAdjustments).doc(orderId);
}

/** `users/{uid}/addresses/{addressId}` - reading it under the caller's own uid IS the ownership check. */
export function userAddressDoc(uid: string, addressId: string) {
  return db().doc(`users/${uid}/addresses/${addressId}`);
}

/** `tryOnSessions/{sessionId}` - server-owned Virtual Try-On session (Stage 4). */
export function tryOnSessionsRef() {
  return db().collection(COLLECTIONS.tryOnSessions);
}

export function tryOnSessionDoc(sessionId: string) {
  return tryOnSessionsRef().doc(sessionId);
}

/** `tryOnQuota/{uid}` - the per-user D9 rate-limit counters. */
export function tryOnUserQuotaDoc(uid: string) {
  return db().collection(COLLECTIONS.tryOnQuota).doc(uid);
}

/** `tryOnQuota/_global` - the D9 server-enforced daily cost circuit breaker. */
export function tryOnGlobalQuotaDoc() {
  return db().collection(COLLECTIONS.tryOnQuota).doc(TRY_ON_GLOBAL_QUOTA_DOC_ID);
}

/** `users/{uid}/addressDefault/pointer` - the single authoritative default-address pointer. */
export function userAddressDefaultPointerDoc(uid: string) {
  return db().doc(`users/${uid}/addressDefault/pointer`);
}
