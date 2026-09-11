import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";

import {
  FUNCTIONS_REGION,
  VTO_CLEANUP_BATCH_SIZE,
  VTO_CLEANUP_SCHEDULE,
  VTO_STUCK_SESSION_RECOVERY_MS,
  VTO_UPLOAD_ORPHAN_MAX_AGE_MS,
  VTO_UPLOAD_ORPHAN_SCAN_MAX_FILES,
} from "./config";
import {
  sweepExpiredTryOnMedia,
  sweepOrphanedTryOnUploads,
  sweepStuckTryOnSessions,
} from "./lib/tryOn/sweep";

/**
 * `cleanupExpiredTryOnMedia` (scheduled) - Phase 9.3 Stage 4.
 *
 * Every 30 minutes, runs three independent, best-effort recovery sweeps (see
 * `lib/tryOn/sweep.ts` for each state machine) - a failure in one is isolated
 * and never blocks the others:
 *   1. `sweepExpiredTryOnMedia` - the D4 TTL safety-fallback for `succeeded`
 *      sessions past their 24h result expiry.
 *   2. `sweepStuckTryOnSessions` - recovers a session left `pending`/
 *      `generating` well past `generateTryOn`'s own function timeout (an
 *      unexpected mid-generation fault), marking it `failed` and cleaning up
 *      any orphaned Storage objects it may have left behind.
 *   3. `sweepOrphanedTryOnUploads` - a Storage-level backstop for a
 *      person-photo upload that outlives any plausible in-flight call,
 *      independent of any Firestore record (covers a client that uploaded
 *      and never called `generateTryOn` at all).
 * No secrets bound - Firestore/Storage only, via the Admin SDK.
 */
export const cleanupExpiredTryOnMedia = onSchedule(
  {
    region: FUNCTIONS_REGION,
    schedule: VTO_CLEANUP_SCHEDULE,
    memory: "256MiB",
    timeoutSeconds: 120,
    // One sweep at a time - every mutation re-checks session state in its own
    // transaction, so overlap would be harmless, but there is no reason to
    // allow it.
    maxInstances: 1,
    retryCount: 0,
  },
  async () => {
    const nowMs = Date.now();

    try {
      const summary = await sweepExpiredTryOnMedia({ nowMs, batchSize: VTO_CLEANUP_BATCH_SIZE });
      logger.info("cleanupExpiredTryOnMedia: expired-media run finished", summary);
    } catch (err) {
      logger.error("cleanupExpiredTryOnMedia: expired-media sweep failed", {
        errorName: (err as { name?: unknown })?.name,
        errorCode: (err as { code?: unknown })?.code,
      });
    }

    try {
      const summary = await sweepStuckTryOnSessions({
        nowMs,
        staleMs: VTO_STUCK_SESSION_RECOVERY_MS,
        batchSize: VTO_CLEANUP_BATCH_SIZE,
      });
      logger.info("cleanupExpiredTryOnMedia: stuck-session run finished", summary);
    } catch (err) {
      logger.error("cleanupExpiredTryOnMedia: stuck-session sweep failed", {
        errorName: (err as { name?: unknown })?.name,
        errorCode: (err as { code?: unknown })?.code,
      });
    }

    try {
      const summary = await sweepOrphanedTryOnUploads({
        nowMs,
        olderThanMs: VTO_UPLOAD_ORPHAN_MAX_AGE_MS,
        maxFiles: VTO_UPLOAD_ORPHAN_SCAN_MAX_FILES,
      });
      logger.info("cleanupExpiredTryOnMedia: orphan-upload run finished", summary);
    } catch (err) {
      logger.error("cleanupExpiredTryOnMedia: orphan-upload sweep failed", {
        errorName: (err as { name?: unknown })?.name,
        errorCode: (err as { code?: unknown })?.code,
      });
    }
  },
);
