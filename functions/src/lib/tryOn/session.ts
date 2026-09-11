import { createHash } from "node:crypto";

/**
 * `tryOnSessions/{sessionId}` - the server-owned Virtual Try-On session
 * (Phase 9.3 Stage 4). Mirrors `../checkoutSession.ts`'s shape and reasoning
 * exactly: a deterministic id from `(uid, idempotencyKey)` so a client retry
 * with the SAME key always resolves to the SAME document - no query, no
 * index, and a second attempt can never create a second billable job
 * (UC-15 4B "duplicate request: not processed twice").
 */

export const TRY_ON_SESSIONS_COLLECTION = "tryOnSessions";

export type TryOnSessionStatus = "pending" | "generating" | "succeeded" | "failed" | "expired";

const TERMINAL_STATUSES: ReadonlySet<TryOnSessionStatus> = new Set([
  "succeeded",
  "failed",
  "expired",
]);

export function isTerminalTryOnStatus(status: TryOnSessionStatus): boolean {
  return TERMINAL_STATUSES.has(status);
}

/**
 * Deterministic session id from `(userId, idempotencyKey)` - namespaced by
 * uid and hashed (SHA-256, hex) so it is always a valid Firestore id, carries
 * no PII, and one user's key can never collide with another's. The client
 * derives the SAME id (identical algorithm) to know where to upload its
 * person photo (`users/{uid}/tryOnUploads/{sessionId}.jpg`) BEFORE calling
 * `generateTryOn`.
 */
export function tryOnSessionIdFor(userId: string, idempotencyKey: string): string {
  return createHash("sha256").update(`${userId} ${idempotencyKey}`).digest("hex");
}

/** The exact, owner-scoped Storage object path for a session's person photo.
 *  Always `.jpg` - the documented client design downscales/re-encodes every
 *  picked photo to JPEG before upload (mirrors the prototype's
 *  `image_picker` `imageQuality` pattern, tracker §4.10); the actual bytes
 *  are still independently signature-verified server-side regardless of the
 *  path extension (`imageSniff.ts`). */
export function tryOnUploadPath(uid: string, sessionId: string): string {
  return `users/${uid}/tryOnUploads/${sessionId}.jpg`;
}

/**
 * The exact, owner-scoped Storage object path for a session's result image.
 * `ext` defaults to `jpg` but the WRITE side always passes the extension
 * matching the provider output's actually-verified content type (Gemini
 * image output is commonly PNG) - so a PNG result is never saved under a
 * misleading `.jpg` name.
 */
export function tryOnResultPath(uid: string, sessionId: string, ext: "jpg" | "png" = "jpg"): string {
  return `users/${uid}/tryOnResults/${sessionId}.${ext}`;
}

/**
 * The two - and only two - Storage paths a result for `(uid, sessionId)`
 * could ever legitimately live at. A cleanup pass that needs to remove "the
 * result for this session" (the TTL sweep, Auth-deletion cleanup) derives
 * and deletes both, best-effort, rather than trusting an arbitrary stored
 * path string - deleting a nonexistent object is a safe no-op, so trying
 * both candidates is always safe and never touches anything this
 * `(uid, sessionId)` does not itself own.
 */
export function tryOnResultCandidatePaths(uid: string, sessionId: string): string[] {
  return [tryOnResultPath(uid, sessionId, "jpg"), tryOnResultPath(uid, sessionId, "png")];
}

/** `true` only when `path` is exactly one of `(uid, sessionId)`'s own two possible result paths. */
export function isOwnResultPath(uid: string, sessionId: string, path: string): boolean {
  return tryOnResultCandidatePaths(uid, sessionId).includes(path);
}

/** Coerce a Firestore `Timestamp` (or a plain `{_seconds}` / number) to epoch ms. */
export function timestampToMillis(value: unknown): number | null {
  if (value && typeof value === "object") {
    const maybe = value as { toMillis?: unknown; _seconds?: unknown; _nanoseconds?: unknown };
    if (typeof maybe.toMillis === "function") {
      const ms = (maybe.toMillis as () => number)();
      return Number.isFinite(ms) ? ms : null;
    }
    if (typeof maybe._seconds === "number") {
      const nanos = typeof maybe._nanoseconds === "number" ? maybe._nanoseconds : 0;
      return maybe._seconds * 1000 + Math.floor(nanos / 1e6);
    }
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

export interface TryOnSessionDoc {
  userId: string;
  productId: string;
  colorKey: string;
  size: string | null;
  garmentStoragePath: string;
  garmentCategory: string;
  status: TryOnSessionStatus;
  failureReason: string | null;
  resultPath: string | null;
  provider: string;
  providerModel: string;
  idempotencyKey: string;
  /** Server time the consent for THIS attempt was recorded (D5). */
  consentAt: unknown;
  createdAt: unknown;
  updatedAt: unknown;
  /** Set only once `status == 'succeeded'` - the D4 TTL-sweep safety net deadline. */
  expiresAt: unknown;
}

export interface BuildPendingSessionParams {
  userId: string;
  productId: string;
  colorKey: string;
  size: string | null;
  garmentStoragePath: string;
  garmentCategory: string;
  idempotencyKey: string;
  provider: string;
  providerModel: string;
  serverTimestamp: unknown;
}

/** Build the initial `pending` session document. Pure - Firestore sentinels are inputs. */
export function buildPendingSessionDoc(params: BuildPendingSessionParams): TryOnSessionDoc {
  return {
    userId: params.userId,
    productId: params.productId,
    colorKey: params.colorKey,
    size: params.size,
    garmentStoragePath: params.garmentStoragePath,
    garmentCategory: params.garmentCategory,
    status: "pending",
    failureReason: null,
    resultPath: null,
    provider: params.provider,
    providerModel: params.providerModel,
    idempotencyKey: params.idempotencyKey,
    consentAt: params.serverTimestamp,
    createdAt: params.serverTimestamp,
    updatedAt: params.serverTimestamp,
    expiresAt: null,
  };
}

export type ExistingSessionVerdict =
  | { kind: "foreign" }
  | { kind: "succeeded"; resultPath: string; expiresAtMs: number }
  | { kind: "attempt_closed" }
  | { kind: "in_progress" }
  | { kind: "stale" };

/**
 * Decide what to do when a session document already exists for this
 * `(uid, idempotencyKey)` - i.e. the caller is retrying (or racing itself).
 * Pure - operates on the raw document data, the caller's own uid + this
 * session's own id, and now.
 *
 *   - a DIFFERENT owner (hash-collision defence, mirrors checkout) -> foreign
 *   - `succeeded` WITH a `resultPath` that is provably this session's own
 *     (`isOwnResultPath`) AND a parseable `expiresAt` that has NOT yet
 *     passed -> hand back the cached result + its real expiry, no new
 *     provider call. A `succeeded` session whose `resultPath`/`expiresAt` is
 *     missing, foreign, unparseable, OR already past `expiresAt` (the D4 TTL
 *     sweep runs only every 30 min, so a session can sit logically expired
 *     for a while before it is actually swept) is treated the same as a
 *     closed attempt below - fail closed, never hand back a result whose
 *     stated lifetime has already ended, and never guess or trust an
 *     unverified path (defence in depth: `tryOnSessions` is never
 *     client-writable, but nothing here should depend on that alone).
 *   - `failed` / `expired` -> the attempt is closed; the client must retry
 *     with a NEW idempotency key (never silently reruns a failed job)
 *   - `pending` / `generating` and still fresh -> genuinely in flight;
 *     refuse rather than risk a second concurrent provider call
 *   - `pending` / `generating` but older than `staleMs` (a crashed prior
 *     invocation) -> `stale`, so the caller can safely treat it as a fresh
 *     attempt instead of being wedged forever
 */
export function classifyExistingTryOnSession(
  data: Record<string, unknown>,
  callerUid: string,
  sessionId: string,
  nowMs: number,
  staleMs: number,
): ExistingSessionVerdict {
  if (data.userId !== callerUid) {
    return { kind: "foreign" };
  }

  const status = data.status as TryOnSessionStatus | undefined;
  if (status === "succeeded") {
    const resultPath = typeof data.resultPath === "string" ? data.resultPath : null;
    const expiresAtMs = timestampToMillis(data.expiresAt);
    if (
      resultPath !== null &&
      isOwnResultPath(callerUid, sessionId, resultPath) &&
      expiresAtMs !== null &&
      expiresAtMs > nowMs
    ) {
      return { kind: "succeeded", resultPath, expiresAtMs };
    }
    // Missing/foreign/unparseable, OR the TTL has already passed (the sweep
    // just hasn't run yet) - fail closed rather than hand back a result
    // whose stated lifetime has ended.
    return { kind: "attempt_closed" };
  }
  if (status === "failed" || status === "expired") {
    return { kind: "attempt_closed" };
  }
  if (status === "pending" || status === "generating") {
    const updatedMs = timestampToMillis(data.updatedAt) ?? timestampToMillis(data.createdAt);
    if (updatedMs !== null && nowMs - updatedMs > staleMs) {
      return { kind: "stale" };
    }
    return { kind: "in_progress" };
  }
  // Unknown / corrupt status - never treat as resumable.
  return { kind: "attempt_closed" };
}
