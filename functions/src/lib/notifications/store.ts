import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { db } from "../firestore";
import {
  DEVICE_TOKENS_COLLECTION,
  INBOX_TTL_MS,
  LEDGER_TTL_MS,
  NOTIFICATIONS_SUBCOLLECTION,
  NOTIFICATION_EVENTS_COLLECTION,
  NOTIFICATION_PREFS_DOC_ID,
  NOTIFICATION_SETTINGS_SUBCOLLECTION,
} from "./constants";
import { cooldownElapsed } from "./dedupe";
import { timestampMillis } from "./events";
import type { RawPrefs } from "./prefs";
import { deviceTokenDocId } from "./tokens";
import type { RenderedNotification } from "./types";

/**
 * Firestore accessors for the notification system (Admin SDK - bypasses
 * `firestore.rules`, which deny every client path to `deviceTokens` and
 * `notificationEvents` and make the inbox server-written). Paths are
 * centralised here so a typo can't read/write the wrong place.
 */

export function deviceTokensRef() {
  return db().collection(DEVICE_TOKENS_COLLECTION);
}

export function deviceTokenDoc(token: string) {
  return deviceTokensRef().doc(deviceTokenDocId(token));
}

export function notificationEventDoc(key: string) {
  return db().collection(NOTIFICATION_EVENTS_COLLECTION).doc(key);
}

export function inboxRef(uid: string) {
  return db().collection(`users/${uid}/${NOTIFICATIONS_SUBCOLLECTION}`);
}

export function prefsDoc(uid: string) {
  return db().doc(
    `users/${uid}/${NOTIFICATION_SETTINGS_SUBCOLLECTION}/${NOTIFICATION_PREFS_DOC_ID}`,
  );
}

export async function readPrefs(uid: string): Promise<RawPrefs> {
  const snap = await prefsDoc(uid).get();
  return snap.exists ? (snap.data() as Record<string, unknown>) : null;
}

export interface DeviceTokenRecord {
  uid: string;
  token: string;
  role: string;
}

function toRecord(data: Record<string, unknown>): DeviceTokenRecord | null {
  if (
    typeof data.uid !== "string" ||
    typeof data.token !== "string" ||
    data.token.length === 0
  ) {
    return null;
  }
  return { uid: data.uid, token: data.token, role: String(data.role ?? "customer") };
}

export async function tokensForUser(uid: string): Promise<DeviceTokenRecord[]> {
  const snap = await deviceTokensRef().where("uid", "==", uid).get();
  return snap.docs
    .map((d) => toRecord(d.data()))
    .filter((r): r is DeviceTokenRecord => r !== null);
}

/** Every registered device whose server-stamped role is `superAdmin`. The
 *  caller MUST still re-verify each uid's live claim (`verifyAdmin`) - the
 *  stamped role can go stale if an admin is later demoted. */
export async function tokensForAdmins(): Promise<DeviceTokenRecord[]> {
  const snap = await deviceTokensRef().where("role", "==", "superAdmin").get();
  return snap.docs
    .map((d) => toRecord(d.data()))
    .filter((r): r is DeviceTokenRecord => r !== null);
}

/** Delete the `deviceTokens` docs for dead tokens (idempotent). */
export async function pruneDeviceTokens(tokens: readonly string[]): Promise<void> {
  if (tokens.length === 0) return;
  const batch = db().batch();
  for (const t of tokens) batch.delete(deviceTokenDoc(t));
  await batch.commit();
}

// --------------------------------------------------------------- inbox ---

export type InboxWriteResult = "created" | "duplicate";

/** Create the customer inbox row at the deterministic dedupe-key id.
 *  ALREADY_EXISTS == this exact event was already processed (a duplicate
 *  trigger delivery) -> `duplicate`. */
export async function createInboxRow(
  uid: string,
  key: string,
  rendered: RenderedNotification,
  nowMs: number,
): Promise<InboxWriteResult> {
  try {
    await inboxRef(uid)
      .doc(key)
      .create({
        type: rendered.type,
        title: rendered.title,
        body: rendered.body,
        route: rendered.route,
        entityId: rendered.entityId,
        createdAt: FieldValue.serverTimestamp(),
        readAt: null,
        pushed: false,
        pushOutcome: "pending",
        expireAt: Timestamp.fromMillis(nowMs + INBOX_TTL_MS),
      });
    return "created";
  } catch (err) {
    if (isAlreadyExists(err)) return "duplicate";
    throw err;
  }
}

export async function setInboxPushOutcome(
  uid: string,
  key: string,
  pushed: boolean,
  pushOutcome: string,
): Promise<void> {
  await inboxRef(uid).doc(key).update({ pushed, pushOutcome });
}

function isAlreadyExists(err: unknown): boolean {
  const e = err as { code?: unknown; message?: unknown };
  return (
    e?.code === 6 ||
    e?.code === "already-exists" ||
    (typeof e?.message === "string" && e.message.includes("ALREADY_EXISTS"))
  );
}

// -------------------------------------------------------- admin ledger ---

export type LedgerClaim = "claimed" | "duplicate" | "cooling";

/**
 * Atomically claim an admin alert in the server-only `notificationEvents`
 * ledger. First claim -> `claimed`. A later call returns `duplicate` when no
 * cooldown applies, or `cooling` while inside `cooldownMs`; once the cooldown
 * has fully elapsed it re-claims (`claimed`, bumping `count`/`lastSentAt`).
 */
export async function claimAdminLedger(
  key: string,
  type: string,
  entityId: string | null,
  nowMs: number,
  cooldownMs: number | null,
): Promise<LedgerClaim> {
  const ref = notificationEventDoc(key);
  return db().runTransaction<LedgerClaim>(async (tx) => {
    const snap = await tx.get(ref);
    const expireAt = Timestamp.fromMillis(nowMs + LEDGER_TTL_MS);
    if (!snap.exists) {
      tx.create(ref, {
        type,
        entityId,
        firstSentAt: Timestamp.fromMillis(nowMs),
        lastSentAt: Timestamp.fromMillis(nowMs),
        count: 1,
        expireAt,
      });
      return "claimed";
    }
    if (cooldownMs === null) return "duplicate";
    const data = snap.data() as Record<string, unknown>;
    if (!cooldownElapsed(timestampMillis(data.lastSentAt), nowMs, cooldownMs)) return "cooling";
    tx.update(ref, {
      lastSentAt: Timestamp.fromMillis(nowMs),
      count: FieldValue.increment(1),
      expireAt,
    });
    return "claimed";
  });
}
