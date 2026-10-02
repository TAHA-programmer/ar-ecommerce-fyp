import { onCall } from "firebase-functions/v2/https";

import { FUNCTIONS_REGION } from "./config";
import { registerDeviceHandler } from "./lib/notifications/devices";

/**
 * `registerDevice` (callable) - FCM notifications (`26_FCM_NOTIFICATIONS_PLAN.md`
 * §4.7). Stores/refreshes the caller's FCM token in the server-only
 * `deviceTokens` collection. The role is stamped from the VERIFIED ID-token
 * claim, never the request body. NOT gated by `NOTIFICATIONS_ENABLED`.
 */
export const registerDevice = onCall(
  { region: FUNCTIONS_REGION, memory: "256MiB", timeoutSeconds: 30, maxInstances: 10 },
  (request) =>
    registerDeviceHandler({
      authUid: request.auth?.uid,
      authRole: request.auth?.token?.role,
      data: request.data,
      nowMs: Date.now(),
    }),
);
