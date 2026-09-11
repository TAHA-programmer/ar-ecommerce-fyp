import { defineSecret } from "firebase-functions/params";

/**
 * Cloud Functions region for every TWin AR function (approved: us-central1).
 * Firestore is in the `nam5` multi-region; `us-central1` is the standard,
 * lowest-latency Functions region for it.
 */
export const FUNCTIONS_REGION = "us-central1";

/**
 * Presentment + settlement currency for every PaymentIntent. `Rs` == PKR
 * (reference pack Decisions Log). PKR is a standard two-decimal currency
 * (not zero-decimal) - see `lib/currency.ts`.
 */
export const ORDER_CURRENCY = "pkr";

/**
 * Tag written to PaymentIntent metadata (`appPhase`) so a PaymentIntent
 * created by this subphase is identifiable in the Stripe dashboard and by
 * the Phase 8.13.3 webhook. Not security-sensitive.
 */
export const PAYMENT_INTENT_PHASE_TAG = "twin_ar_8_13_2";

/**
 * Phase 8.13.4 - expired-reservation sweep (`releaseExpiredReservations`).
 *
 * Runs every 5 minutes. Each run processes at most `BATCH_SIZE` expired
 * `reserved` sessions using the `(status, expiresAt)` composite index; if
 * there are more, the next run continues (the work is idempotent, so a
 * missed or overlapping run is harmless).
 */
export const RESERVATION_SWEEP_SCHEDULE = "every 5 minutes";
export const RESERVATION_SWEEP_BATCH_SIZE = 20;

/**
 * Secret Manager secret NAMES ONLY.
 *
 * The secret VALUES are provided out-of-band by the project owner:
 *   firebase functions:secrets:set STRIPE_SECRET_KEY
 *   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET   (Phase 8.13.3)
 *
 * They are bound to individual functions at deploy time via
 * `secrets: [stripeSecretKey]` and read at runtime with `.value()`. A secret
 * value is NEVER written to source, a committed `.env`/`.runtimeconfig.json`,
 * a log line, a test fixture, or documentation.
 *
 * `stripeWebhookSecret` is declared here for a single source of truth but is
 * only consumed by the webhook function added in the later Phase 8.13.3
 * subphase.
 */
export const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
export const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");

/**
 * Phase 9.3 Stage 4 - Virtual Try-On.
 *
 * `GEMINI_API_KEY` is the Gemini Developer API key for the LOCKED provider
 * (developer decision D2, `21_PHASE_9_3_VIRTUAL_TRYON_TRACKER.md` - paid tier
 * only, never the unpaid tier, per D3). Bound only to `generateTryOn`. The
 * value is provided out-of-band:
 *   firebase functions:secrets:set GEMINI_API_KEY
 * Never read from source, a committed `.env`, `process.env` defaults, a log
 * line, a test fixture, or documentation. This Stage-4 implementation pass
 * does NOT set the real secret value and makes NO real Gemini call - every
 * automated test injects a fake provider / fake `fetch`.
 */
export const geminiApiKey = defineSecret("GEMINI_API_KEY");

/** The Stage-1-locked provider + model identifiers (recorded, not secret). */
export const VTO_PROVIDER_NAME = "gemini";
export const VTO_PROVIDER_MODEL = "gemini-2.5-flash-image";

/**
 * Generative Language API `generateContent` REST endpoint for the locked
 * model. Called with a plain `fetch` (no SDK) per the tracker's §9.1 design -
 * the key is sent as the `x-goog-api-key` header, never a query parameter, so
 * it can never appear in a logged URL.
 */
export const VTO_GEMINI_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent";

/** Bounded provider call - no retry anywhere in this path (D9 / UC-15 4B). */
export const VTO_PROVIDER_TIMEOUT_MS = 60_000;

/** Transport ceiling for a customer person-photo upload (mirrors the Stage 3
 *  `VtoGarmentAsset.maxBytes` / R16 AR-model precedent). */
export const VTO_PERSON_PHOTO_MAX_BYTES = 12 * 1024 * 1024;

/** Sanity ceiling on a provider-returned image - a response larger than this
 *  is treated as an internal error, never written to Storage. */
export const VTO_RESULT_MAX_BYTES = 15 * 1024 * 1024;

/**
 * D4: the generated preview is deleted when the customer dismisses it or
 * leaves the result flow (Stage 5, not yet implemented). This TTL is ONLY the
 * safety-fallback sweep for a result that path somehow missed - today, since
 * Stage 5 does not exist yet, it is the ONLY deletion path for a result and
 * is expected to fire for every session.
 */
export const VTO_RESULT_TTL_MS = 24 * 60 * 60 * 1000;

export const VTO_CLEANUP_SCHEDULE = "every 30 minutes";
export const VTO_CLEANUP_BATCH_SIZE = 50;

/** D9: per-user and global server-enforced request caps, checked-and-bumped
 *  transactionally BEFORE any provider call - a real cost circuit breaker. */
export const VTO_RATE_LIMIT_PER_USER_HOUR = 5;
export const VTO_RATE_LIMIT_PER_USER_HOUR_MS = 60 * 60 * 1000;
export const VTO_RATE_LIMIT_PER_USER_DAY = 10;
export const VTO_RATE_LIMIT_PER_USER_DAY_MS = 24 * 60 * 60 * 1000;
export const VTO_RATE_LIMIT_GLOBAL_DAY = 50;
export const VTO_RATE_LIMIT_GLOBAL_DAY_MS = 24 * 60 * 60 * 1000;

/** `tryOnSessions/{sessionId}` document ids are unguessable, but a session
 *  left `pending`/`generating` past this window (a crashed invocation) is
 *  treated as abandoned rather than blocking the same (uid, idempotencyKey)
 *  forever - the caller may retry with a NEW idempotency key. */
export const VTO_SESSION_STALE_MS = 5 * 60 * 1000;

/**
 * `cleanupExpiredTryOnMedia` hardening pass (2026-09-11) - two extra,
 * best-effort recovery sweeps run in the same scheduled invocation:
 *
 *   - a `tryOnSessions` doc stuck in `pending`/`generating` well past
 *     `generateTryOn`'s own `timeoutSeconds: 120` cap can only mean the
 *     invocation crashed/was killed before it could mark a terminal status
 *     (an unexpected Firestore/Storage fault, a container recycle, ...).
 *     Reusing `VTO_SESSION_STALE_MS` (5 min - well past 120s) as the
 *     recovery threshold, the sweep marks it `failed` and best-effort
 *     deletes any orphaned upload/result objects that attempt may have left
 *     behind.
 *   - a person-photo upload under `users/*\/tryOnUploads/**` is deleted
 *     unconditionally by `generateTryOn` itself (success or failure) the
 *     moment its invocation runs at all; one that survives
 *     `VTO_UPLOAD_ORPHAN_MAX_AGE_MS` can only be a genuine orphan - either
 *     the client uploaded and never called `generateTryOn`, or the one
 *     invocation that could have deleted it never got the chance to run.
 */
export const VTO_STUCK_SESSION_RECOVERY_MS = VTO_SESSION_STALE_MS;
export const VTO_UPLOAD_ORPHAN_MAX_AGE_MS = 2 * 60 * 60 * 1000; // 2 hours
/** Upper bound on objects inspected by the orphan-upload prefix scan per run
 *  - generous at this app's scale; a production-volume rewrite would
 *  maintain a Firestore index of outstanding uploads instead of scanning
 *  Storage directly. */
export const VTO_UPLOAD_ORPHAN_SCAN_MAX_FILES = 1000;
