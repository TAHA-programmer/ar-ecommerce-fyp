/**
 * FCM notification library (`26_FCM_NOTIFICATIONS_PLAN.md`) - Stage S1.
 *
 * Pure, side-effect-free building blocks: catalogue + copy, dedupe keys,
 * preference evaluation, event classifiers, token-registration helpers,
 * message/payload builders, an injectable-messaging send/prune routine and a
 * per-recipient cap. NOTHING here is imported by `index.ts` (the deployed
 * entry point), no trigger or callable exists yet (Stage S3), and no
 * Firestore/FCM call is made by importing it.
 */
export * from "./constants";
export * from "./types";
export * from "./catalog";
export * from "./dedupe";
export * from "./prefs";
export * from "./events";
export * from "./tokens";
export * from "./payload";
export * from "./send";
export * from "./recipientCap";
