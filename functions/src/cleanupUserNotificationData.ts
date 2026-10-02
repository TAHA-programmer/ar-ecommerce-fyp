import * as functionsV1 from "firebase-functions/v1";
import * as logger from "firebase-functions/logger";

import { FUNCTIONS_REGION } from "./config";
import { cleanupNotificationDataForUser } from "./lib/notifications/devices";

/**
 * `cleanupUserNotificationData` (Auth user-deletion trigger) - third sibling
 * of `cleanupUserTryOnData` / `cleanupUserReviewsData` (same
 * `auth.user().onDelete()` event; each fires independently). Deletes the
 * deleted account's device tokens, notification inbox and preferences.
 * Re-runnable. NOT gated by the kill-switch (deleting data is always right).
 */
export const cleanupUserNotificationData = functionsV1
  .region(FUNCTIONS_REGION)
  .auth.user()
  .onDelete(async (user) => {
    try {
      await cleanupNotificationDataForUser(user.uid);
      logger.info("cleanupUserNotificationData: cleanup complete", { uid: user.uid });
    } catch (err) {
      logger.error("cleanupUserNotificationData: cleanup failed", {
        uid: user.uid,
        name: (err as { name?: unknown })?.name,
      });
      throw err;
    }
  });
