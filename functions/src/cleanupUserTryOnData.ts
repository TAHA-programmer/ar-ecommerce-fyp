import * as functionsV1 from "firebase-functions/v1";
import * as logger from "firebase-functions/logger";

import { FUNCTIONS_REGION } from "./config";
import { COLLECTIONS, db, tryOnUserQuotaDoc } from "./lib/firestore";
import { deleteObjectBestEffort, deletePrefixBestEffort } from "./lib/tryOn/storage";
import { tryOnResultCandidatePaths, tryOnUploadPath } from "./lib/tryOn/session";

/**
 * `cleanupUserTryOnData` (Auth user-deletion trigger) - Phase 9.3 Stage 4.
 *
 * When a Firebase Auth account is deleted, this removes every trace of that
 * user's Virtual Try-On data:
 *   - `tryOnQuota/{uid}` (the D9 rate-limit counters);
 *   - every `tryOnSessions/{id}` document with `userId == uid`, in bounded
 *     pages, deleting that session's own result (and, defensively, any stray
 *     upload) object first;
 *   - a final prefix sweep of `users/{uid}/tryOnUploads/**` and
 *     `users/{uid}/tryOnResults/**` as a backstop for any object a
 *     crashed/partial prior invocation left behind (there should never be
 *     one under the normal D4 unconditional-delete path, but this makes the
 *     cleanup complete regardless).
 *
 * A user's `users/{uid}` profile document and other subcollections (orders,
 * addresses, cart, favourites, ...) are NOT touched here - out of scope for
 * Stage 4, unrelated to Virtual Try-On.
 */

const SESSION_PAGE_SIZE = 200;
const MAX_PAGES = 25; // 5,000 sessions - generous; logs a warning if exceeded

export async function cleanupTryOnDataForUser(uid: string): Promise<void> {
  await tryOnUserQuotaDoc(uid)
    .delete()
    .catch((err) =>
      logger.warn("cleanupUserTryOnData: could not delete tryOnQuota doc", {
        name: (err as { name?: unknown })?.name,
      }),
    );

  let pages = 0;
  for (;;) {
    pages += 1;
    const snap = await db()
      .collection(COLLECTIONS.tryOnSessions)
      .where("userId", "==", uid)
      .limit(SESSION_PAGE_SIZE)
      .get();
    if (snap.empty) break;

    await Promise.all(
      snap.docs.map(async (doc) => {
        // Never trust the stored `resultPath` field as a delete target
        // (2026-09-11 hardening) - always derive both candidate paths this
        // session could ever legitimately own from `(uid, sessionId)` and
        // delete both, best-effort. Deleting a nonexistent object is a safe
        // no-op, so this can never touch anything outside this user's own
        // Storage tree even from a corrupted document.
        for (const path of tryOnResultCandidatePaths(uid, doc.id)) {
          await deleteObjectBestEffort(path, "cleanupUserTryOnData");
        }
        await deleteObjectBestEffort(tryOnUploadPath(uid, doc.id), "cleanupUserTryOnData");
        await doc.ref.delete();
      }),
    );

    if (snap.size < SESSION_PAGE_SIZE) break;
    if (pages >= MAX_PAGES) {
      logger.warn("cleanupUserTryOnData: reached the page cap - some sessions may remain", { uid });
      break;
    }
  }

  await deletePrefixBestEffort(`users/${uid}/tryOnUploads/`, "cleanupUserTryOnData");
  await deletePrefixBestEffort(`users/${uid}/tryOnResults/`, "cleanupUserTryOnData");
}

export const cleanupUserTryOnData = functionsV1
  .region(FUNCTIONS_REGION)
  .auth.user()
  .onDelete(async (user) => {
    try {
      await cleanupTryOnDataForUser(user.uid);
      logger.info("cleanupUserTryOnData: cleanup complete", { uid: user.uid });
    } catch (err) {
      logger.error("cleanupUserTryOnData: cleanup failed", {
        uid: user.uid,
        name: (err as { name?: unknown })?.name,
      });
      throw err;
    }
  });
