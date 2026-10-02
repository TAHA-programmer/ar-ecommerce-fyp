import { onCall } from "firebase-functions/v2/https";

import { FUNCTIONS_REGION } from "./config";
import { unregisterDeviceHandler } from "./lib/notifications/devices";

/** `unregisterDevice` (callable) - deletes the caller's OWN token doc
 *  (idempotent; a token owned by someone else is untouched). */
export const unregisterDevice = onCall(
  { region: FUNCTIONS_REGION, memory: "256MiB", timeoutSeconds: 30, maxInstances: 10 },
  (request) =>
    unregisterDeviceHandler({ authUid: request.auth?.uid, data: request.data }),
);
