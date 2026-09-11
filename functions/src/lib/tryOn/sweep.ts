import { FieldValue, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import { COLLECTIONS, db, tryOnSessionDoc } from "../firestore";
import { deleteObjectBestEffort, listStaleObjectsUnderPrefix } from "./storage";
import { timestampToMillis, tryOnResultCandidatePaths, tryOnUploadPath } from "./session";

/**
 * `cleanupExpiredTryOnMedia` (Phase 9.3 Stage 4) - three independent,
 * best-effort recovery sweeps run every 30 minutes:
 *
 *   1. {@link sweepExpiredTryOnMedia} - the D4 SAFETY-FALLBACK TTL sweep. The
 *      primary deletion path is the customer dismissing/leaving the result
 *      (Stage 5, not yet implemented) - today, since Stage 5 does not exist,
 *      EVERY successful session's result is expected to be cleaned up here.
 *   2. {@link sweepStuckTryOnSessions} - recovers a session left `pending`/
 *      `generating` well past `generateTryOn`'s own 120s function timeout
 *      (2026-09-11 hardening pass - an unexpected Firestore/Storage fault
 *      mid-generation could otherwise wedge a session forever and orphan any
 *      result it already wrote).
 *   3. {@link sweepOrphanedTryOnUploads} - a Storage-level backstop
 *      independent of any Firestore record, for a person-photo upload that
 *      outlives any plausible in-flight `generateTryOn` call (2026-09-11
 *      hardening pass - covers a client that uploaded and never called the
 *      function at all, which has no session document to key off of).
 */

export interface TryOnSweepSummary {
  scannedAt: number;
  batchSize: number;
  scanned: number;
  hadMore: boolean;
  outcomes: Record<string, number>;
  errors: number;
}

// ---------------------------------------------------------------------------
// 1. Expired (succeeded, TTL-passed) result media
// ---------------------------------------------------------------------------

export type TryOnSweepOutcome = { kind: "expired" } | { kind: "skipped" } | { kind: "session_corrupt" };

export async function sweepExpiredTryOnMedia(args: {
  nowMs: number;
  batchSize: number;
}): Promise<TryOnSweepSummary> {
  const cutoff = Timestamp.fromMillis(args.nowMs);
  const snap = await db()
    .collection(COLLECTIONS.tryOnSessions)
    .where("status", "==", "succeeded")
    .where("expiresAt", "<=", cutoff)
    .limit(args.batchSize)
    .get();

  const settled = await Promise.allSettled(
    snap.docs.map((doc) =>
      processExpiredSession(doc.id, (doc.data() ?? {}) as Record<string, unknown>, args.nowMs),
    ),
  );

  const summary = summarize(settled, args.nowMs, args.batchSize, snap.size);
  logger.info("cleanupExpiredTryOnMedia: expired-media sweep complete", summary);
  return summary;
}

async function processExpiredSession(
  sessionId: string,
  data: Record<string, unknown>,
  nowMs: number,
): Promise<TryOnSweepOutcome> {
  const userId = typeof data.userId === "string" ? data.userId : "";
  if (!userId) {
    return { kind: "session_corrupt" };
  }

  // Never trust the stored `resultPath` field as a delete target (2026-09-11
  // hardening - a future bug/migration/console edit could otherwise point
  // this at an arbitrary or another user's object). Always derive the two
  // candidate paths this session could ever legitimately own from
  // `(userId, sessionId)` and delete both, best-effort - a delete of a
  // nonexistent object is a safe no-op, so this needs no matching logic and
  // can never touch anything this session does not itself own.
  for (const path of tryOnResultCandidatePaths(userId, sessionId)) {
    await deleteObjectBestEffort(path, "cleanupExpiredTryOnMedia");
  }
  // Defensive backstop only - the normal `generateTryOn` path already
  // deletes the person upload unconditionally right after generation.
  await deleteObjectBestEffort(tryOnUploadPath(userId, sessionId), "cleanupExpiredTryOnMedia");

  return db().runTransaction<TryOnSweepOutcome>(async (tx) => {
    const ref = tryOnSessionDoc(sessionId);
    const snap = await tx.get(ref);
    if (!snap.exists) {
      return { kind: "session_corrupt" };
    }
    const current = (snap.data() ?? {}) as Record<string, unknown>;
    const expiresMs = timestampToMillis(current.expiresAt);
    if (current.status !== "succeeded" || expiresMs === null || expiresMs > nowMs) {
      // Already handled by another sweep run, or no longer eligible.
      return { kind: "skipped" };
    }
    tx.update(ref, { status: "expired", resultPath: null });
    return { kind: "expired" };
  });
}

// ---------------------------------------------------------------------------
// 2. Stuck pending/generating sessions (unexpected-failure recovery)
// ---------------------------------------------------------------------------

export type StuckSweepOutcome = { kind: "recovered" } | { kind: "skipped" } | { kind: "session_corrupt" };

export async function sweepStuckTryOnSessions(args: {
  nowMs: number;
  staleMs: number;
  batchSize: number;
}): Promise<TryOnSweepSummary> {
  const snap = await db()
    .collection(COLLECTIONS.tryOnSessions)
    .where("status", "in", ["pending", "generating"])
    .limit(args.batchSize)
    .get();

  const settled = await Promise.allSettled(
    snap.docs.map((doc) => recoverStuckSession(doc.id, args.nowMs, args.staleMs)),
  );

  const summary = summarize(settled, args.nowMs, args.batchSize, snap.size);
  logger.info("cleanupExpiredTryOnMedia: stuck-session sweep complete", summary);
  return summary;
}

async function recoverStuckSession(
  sessionId: string,
  nowMs: number,
  staleMs: number,
): Promise<StuckSweepOutcome> {
  const { outcome, userId } = await db().runTransaction<{
    outcome: StuckSweepOutcome;
    userId: string | null;
  }>(async (tx) => {
    const ref = tryOnSessionDoc(sessionId);
    const snap = await tx.get(ref);
    if (!snap.exists) {
      return { outcome: { kind: "session_corrupt" }, userId: null };
    }
    const data = (snap.data() ?? {}) as Record<string, unknown>;
    if (data.status !== "pending" && data.status !== "generating") {
      // Already reached a terminal status (or a stale retry already resumed
      // it) since the outer query ran - nothing to do.
      return { outcome: { kind: "skipped" }, userId: null };
    }
    const updatedMs = timestampToMillis(data.updatedAt) ?? timestampToMillis(data.createdAt);
    if (updatedMs === null || nowMs - updatedMs < staleMs) {
      // Re-checked fresh, inside the transaction, at commit time - genuinely
      // still in flight (or a retry just resumed it); never touch it.
      return { outcome: { kind: "skipped" }, userId: null };
    }
    tx.update(ref, {
      status: "failed",
      failureReason: "stuck_recovered",
      resultPath: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      outcome: { kind: "recovered" },
      userId: typeof data.userId === "string" ? data.userId : null,
    };
  });

  if (outcome.kind === "recovered" && userId) {
    for (const path of tryOnResultCandidatePaths(userId, sessionId)) {
      await deleteObjectBestEffort(path, "cleanupExpiredTryOnMedia:stuckSweep");
    }
    await deleteObjectBestEffort(tryOnUploadPath(userId, sessionId), "cleanupExpiredTryOnMedia:stuckSweep");
  }
  return outcome;
}

// ---------------------------------------------------------------------------
// 3. Orphaned person-photo uploads (no Firestore record needed)
// ---------------------------------------------------------------------------

export interface OrphanUploadSweepSummary {
  scannedAt: number;
  deleted: number;
  errors: number;
}

export async function sweepOrphanedTryOnUploads(args: {
  nowMs: number;
  olderThanMs: number;
  maxFiles: number;
}): Promise<OrphanUploadSweepSummary> {
  const staleNames = await listStaleObjectsUnderPrefix({
    prefix: "users/",
    pathSegment: "/tryOnUploads/",
    nowMs: args.nowMs,
    olderThanMs: args.olderThanMs,
    maxFiles: args.maxFiles,
  });

  let deleted = 0;
  let errors = 0;
  for (const name of staleNames) {
    const ok = await deleteObjectBestEffort(name, "cleanupExpiredTryOnMedia:orphanUploadSweep");
    if (ok) deleted += 1;
    else errors += 1;
  }

  const summary: OrphanUploadSweepSummary = { scannedAt: args.nowMs, deleted, errors };
  logger.info("cleanupExpiredTryOnMedia: orphan-upload sweep complete", {
    ...summary,
    scannedCandidates: staleNames.length,
  });
  return summary;
}

// ---------------------------------------------------------------------------

function summarize(
  settled: PromiseSettledResult<{ kind: string }>[],
  nowMs: number,
  batchSize: number,
  scanned: number,
): TryOnSweepSummary {
  const outcomes: Record<string, number> = {};
  let errors = 0;
  for (const r of settled) {
    if (r.status === "fulfilled") {
      outcomes[r.value.kind] = (outcomes[r.value.kind] ?? 0) + 1;
    } else {
      errors += 1;
      logger.error("cleanupExpiredTryOnMedia: a session threw and was skipped (isolated)", {
        errorName: (r.reason as { name?: unknown })?.name,
      });
    }
  }
  return {
    scannedAt: nowMs,
    batchSize,
    scanned,
    hadMore: scanned === batchSize,
    outcomes,
    errors,
  };
}
