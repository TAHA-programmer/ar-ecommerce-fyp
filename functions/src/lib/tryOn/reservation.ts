import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {
  VTO_PROVIDER_MODEL,
  VTO_PROVIDER_NAME,
  VTO_RATE_LIMIT_GLOBAL_DAY,
  VTO_RATE_LIMIT_GLOBAL_DAY_MS,
  VTO_RATE_LIMIT_PER_USER_DAY,
  VTO_RATE_LIMIT_PER_USER_DAY_MS,
  VTO_RATE_LIMIT_PER_USER_HOUR,
  VTO_RATE_LIMIT_PER_USER_HOUR_MS,
  VTO_SESSION_STALE_MS,
} from "../../config";
import {
  errForbiddenSession,
  errGlobalLimitReached,
  errRateLimited,
  errSessionAttemptClosed,
  errSessionConflict,
  errSessionInProgress,
} from "./errors";
import { db, tryOnGlobalQuotaDoc, tryOnSessionDoc, tryOnUserQuotaDoc } from "../firestore";
import { evaluateGlobalQuota, evaluateUserQuota, windowStateFromData } from "./rateLimit";
import type { ResolvedGarment } from "./eligibility";
import type { ParsedGenerateTryOnRequest } from "./validation";
import {
  buildPendingSessionDoc,
  classifyExistingTryOnSession,
  timestampToMillis,
} from "./session";

/**
 * The Firestore side of `generateTryOn` (Phase 9.3 Stage 4) - ONE transaction
 * that either:
 *   (a) classifies an existing session for this `(uid, idempotencyKey)` and
 *       tells the caller what to do (reuse the cached success, refuse a
 *       closed/in-flight attempt), or
 *   (b) atomically checks-and-bumps the D9 per-user + global rate-limit
 *       counters and creates the `pending` session - BEFORE any provider
 *       call, so a request that is over any cap makes zero billable calls
 *       (a real cost circuit breaker, not just a monitoring alert).
 *
 * No provider / Storage I/O happens inside this transaction - only Firestore
 * reads/writes, exactly like `../reservation.ts`'s checkout equivalent. Every
 * refusal is thrown as the final customer-safe `HttpsError` directly from
 * inside the transaction callback (mirroring `../reservation.ts`); the outer
 * `catch` only maps a genuinely unexpected Firestore fault.
 */

export type ReserveOutcome =
  | { kind: "created" }
  | { kind: "succeeded_cached"; resultPath: string; expiresAtMs: number };

export async function reserveTryOnSessionOrClassify(args: {
  uid: string;
  sessionId: string;
  request: ParsedGenerateTryOnRequest;
  garment: ResolvedGarment;
  nowMs: number;
}): Promise<ReserveOutcome> {
  const { uid, sessionId, request, garment, nowMs } = args;
  const sessionRef = tryOnSessionDoc(sessionId);
  const userQuotaRef = tryOnUserQuotaDoc(uid);
  const globalQuotaRef = tryOnGlobalQuotaDoc();

  try {
    return await db().runTransaction<ReserveOutcome>(async (tx) => {
      // ---- READS (all reads precede all writes) ----
      const sessionSnap = await tx.get(sessionRef);

      if (sessionSnap.exists) {
        const data = (sessionSnap.data() ?? {}) as Record<string, unknown>;
        const verdict = classifyExistingTryOnSession(data, uid, sessionId, nowMs, VTO_SESSION_STALE_MS);
        switch (verdict.kind) {
          case "foreign":
            throw errForbiddenSession();
          case "succeeded":
            return {
              kind: "succeeded_cached",
              resultPath: verdict.resultPath,
              expiresAtMs: verdict.expiresAtMs,
            };
          case "attempt_closed":
            throw errSessionAttemptClosed();
          case "in_progress":
            throw errSessionInProgress();
          case "stale":
            // Falls through to the fresh-creation path below - a crashed
            // prior invocation never wedges the same idempotency key forever.
            break;
        }
      }

      const [userQuotaSnap, globalQuotaSnap] = await Promise.all([
        tx.get(userQuotaRef),
        tx.get(globalQuotaRef),
      ]);
      const userData = userQuotaSnap.exists
        ? (userQuotaSnap.data() as Record<string, unknown>)
        : undefined;
      const globalData = globalQuotaSnap.exists
        ? (globalQuotaSnap.data() as Record<string, unknown>)
        : undefined;

      const userVerdict = evaluateUserQuota(
        {
          hour: windowStateFromData(userData, "hourWindowStart", "hourCount", timestampToMillis),
          day: windowStateFromData(userData, "dayWindowStart", "dayCount", timestampToMillis),
        },
        nowMs,
        {
          hourCap: VTO_RATE_LIMIT_PER_USER_HOUR,
          hourWindowMs: VTO_RATE_LIMIT_PER_USER_HOUR_MS,
          dayCap: VTO_RATE_LIMIT_PER_USER_DAY,
          dayWindowMs: VTO_RATE_LIMIT_PER_USER_DAY_MS,
        },
      );
      if (!userVerdict.allowed) {
        throw errRateLimited();
      }

      const globalVerdict = evaluateGlobalQuota(
        windowStateFromData(globalData, "dayWindowStart", "dayCount", timestampToMillis),
        nowMs,
        { dayCap: VTO_RATE_LIMIT_GLOBAL_DAY, dayWindowMs: VTO_RATE_LIMIT_GLOBAL_DAY_MS },
      );
      if (!globalVerdict.allowed) {
        throw errGlobalLimitReached();
      }

      // ---- WRITES ----
      const serverTimestamp = FieldValue.serverTimestamp();
      tx.set(
        sessionRef,
        buildPendingSessionDoc({
          userId: uid,
          productId: request.productId,
          colorKey: request.colorKey,
          size: request.size,
          garmentStoragePath: garment.storagePath,
          garmentCategory: garment.garmentCategory,
          idempotencyKey: request.idempotencyKey,
          provider: VTO_PROVIDER_NAME,
          providerModel: VTO_PROVIDER_MODEL,
          serverTimestamp,
        }),
      );
      tx.set(
        userQuotaRef,
        {
          hourWindowStart: Timestamp.fromMillis(userVerdict.nextHour.windowStart),
          hourCount: userVerdict.nextHour.count,
          dayWindowStart: Timestamp.fromMillis(userVerdict.nextDay.windowStart),
          dayCount: userVerdict.nextDay.count,
          updatedAt: serverTimestamp,
        },
        { merge: true },
      );
      tx.set(
        globalQuotaRef,
        {
          dayWindowStart: Timestamp.fromMillis(globalVerdict.nextDay.windowStart),
          dayCount: globalVerdict.nextDay.count,
          updatedAt: serverTimestamp,
        },
        { merge: true },
      );

      return { kind: "created" };
    });
  } catch (err) {
    // A thrown HttpsError (foreign / attempt-closed / in-progress / rate
    // limit) propagates unchanged.
    if (err instanceof HttpsError) {
      throw err;
    }
    logger.error("generateTryOn: reservation transaction failed", {
      sessionId,
      name: (err as { name?: unknown })?.name,
      code: (err as { code?: unknown })?.code,
    });
    throw errSessionConflict();
  }
}
