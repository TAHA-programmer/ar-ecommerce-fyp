import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../firestore";
import { MAX_DEVICES_PER_USER } from "./constants";
import { timestampMillis } from "./events";
import { deviceTokenDoc, deviceTokensRef, inboxRef, prefsDoc } from "./store";
import {
  DeviceRegistrationValidationError,
  deviceTokenExpireAtMs,
  deviceTokenDocId,
  parseRegisterDeviceRequest,
  parseUnregisterDeviceRequest,
  roleFromClaim,
  selectDevicesToEvict,
} from "./tokens";

/**
 * Device-token registration core (plan §4.7), shared by the `registerDevice`
 * / `unregisterDevice` callables and the Auth-deletion cleanup. The role is
 * ALWAYS taken from the verified token claim passed in by the callable
 * wrapper - never from the request body.
 */

export interface RegisterDeviceInput {
  authUid: string | undefined;
  /** `request.auth.token.role` (the verified custom claim). */
  authRole: unknown;
  data: unknown;
  nowMs: number;
}

function invalid(message: string): HttpsError {
  return new HttpsError("invalid-argument", message, { appCode: "INVALID_REQUEST" });
}

function unauthenticated(): HttpsError {
  return new HttpsError("unauthenticated", "You must be signed in to do that.", {
    appCode: "UNAUTHENTICATED",
  });
}

export async function registerDeviceHandler(
  input: RegisterDeviceInput,
): Promise<{ registered: true }> {
  if (!input.authUid) throw unauthenticated();
  const uid = input.authUid;

  let req;
  try {
    req = parseRegisterDeviceRequest(input.data);
  } catch (err) {
    if (err instanceof DeviceRegistrationValidationError) throw invalid(err.message);
    throw err;
  }

  const role = roleFromClaim(input.authRole);
  const ref = deviceTokenDoc(req.token);
  const keepId = deviceTokenDocId(req.token);
  const now = Timestamp.fromMillis(input.nowMs);

  try {
    // Ownership may MOVE: if this token doc exists under another uid (shared
    // device, logout/login), it is overwritten and the previous owner stops
    // receiving. createdAt is kept only when the same uid re-registers.
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const existing = snap.exists ? (snap.data() as Record<string, unknown>) : null;
      const sameOwner = existing !== null && existing.uid === uid;
      tx.set(ref, {
        uid,
        token: req.token,
        role,
        platform: req.platform,
        appVersion: req.appVersion,
        installId: req.installId,
        createdAt: sameOwner && existing?.createdAt ? existing.createdAt : now,
        lastSeenAt: now,
        expireAt: Timestamp.fromMillis(deviceTokenExpireAtMs(input.nowMs)),
      });
    });

    // Hygiene: this install's previous token (FCM token refresh) is dead, and
    // a user is capped at MAX_DEVICES_PER_USER (oldest lastSeenAt evicted).
    const mine = await deviceTokensRef().where("uid", "==", uid).get();
    const staleSameInstall = mine.docs
      .filter((d) => d.id !== keepId && d.data().installId === req.installId)
      .map((d) => d.id);
    const remaining = mine.docs
      .filter((d) => !staleSameInstall.includes(d.id))
      .map((d) => ({
        id: d.id,
        lastSeenMs: timestampMillis(d.data().lastSeenAt) ?? 0,
      }));
    const toDelete = [
      ...staleSameInstall,
      ...selectDevicesToEvict(remaining, keepId, MAX_DEVICES_PER_USER),
    ];
    if (toDelete.length > 0) {
      const batch = db().batch();
      for (const id of toDelete) batch.delete(deviceTokensRef().doc(id));
      await batch.commit();
    }
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error("registerDevice: unexpected failure", { name: (err as { name?: unknown })?.name });
    throw new HttpsError("internal", "Something went wrong. Please try again.", {
      appCode: "INTERNAL",
    });
  }
  return { registered: true };
}

export interface UnregisterDeviceInput {
  authUid: string | undefined;
  data: unknown;
}

/** Deletes the caller's OWN token doc; a token owned by anyone else is left
 *  untouched (and reported as not removed). Idempotent. */
export async function unregisterDeviceHandler(
  input: UnregisterDeviceInput,
): Promise<{ removed: boolean }> {
  if (!input.authUid) throw unauthenticated();
  const uid = input.authUid;

  let token: string;
  try {
    token = parseUnregisterDeviceRequest(input.data).token;
  } catch (err) {
    if (err instanceof DeviceRegistrationValidationError) throw invalid(err.message);
    throw err;
  }

  const ref = deviceTokenDoc(token);
  try {
    return await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists || (snap.data() as Record<string, unknown>).uid !== uid) {
        return { removed: false };
      }
      tx.delete(ref);
      return { removed: true };
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error("unregisterDevice: unexpected failure", {
      name: (err as { name?: unknown })?.name,
    });
    throw new HttpsError("internal", "Something went wrong. Please try again.", {
      appCode: "INTERNAL",
    });
  }
}

/**
 * Auth-deletion cleanup: removes every device token, the whole notification
 * inbox and the preferences doc for a deleted account. Re-runnable.
 */
export async function cleanupNotificationDataForUser(uid: string): Promise<void> {
  for (;;) {
    const snap = await deviceTokensRef().where("uid", "==", uid).limit(100).get();
    if (snap.empty) break;
    const batch = db().batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    if (snap.size < 100) break;
  }
  await db().recursiveDelete(inboxRef(uid));
  await prefsDoc(uid).delete();
}
