import * as logger from "firebase-functions/logger";

import { renderNotification } from "./catalog";
import { RECIPIENT_PUSH_CAP, RECIPIENT_PUSH_WINDOW_MS } from "./constants";
import { buildPushData } from "./payload";
import { categoryAllowedForRole, isPushEnabledByPrefs } from "./prefs";
import { evaluateRecipientCap } from "./recipientCap";
import { sendPush, summarizePushForLog, type MessagingLike, type PushResult } from "./send";
import {
  claimAdminLedger,
  createInboxRow,
  pruneDeviceTokens,
  readPrefs,
  setInboxPushOutcome,
  tokensForAdmins,
  tokensForUser,
} from "./store";
import type {
  AdminNotificationType,
  CustomerNotificationType,
  NotificationParams,
} from "./types";

/**
 * Orchestration for sending notifications (plan §4.1). Everything external is
 * injected (`messaging`, `verifyAdmin`, `nowMs`, `enabled`) so the emulator
 * tests exercise the REAL Firestore logic with a fake FCM and no Auth.
 *
 * Idempotency/duplication rules:
 *  - customer: the inbox row id IS the dedupe key; `create()` ALREADY_EXISTS
 *    means a duplicate trigger delivery -> nothing else happens (no second
 *    push). The inbox row is written REGARDLESS of push prefs / OS state (D7).
 *  - admin: the server-only ledger (`claimAdminLedger`) is claimed first.
 *  - a failed push is never retried (D9: best-effort, the inbox is the
 *    guarantee) and never throws out of here.
 */

export interface NotifyDeps {
  /** The `NOTIFICATIONS_ENABLED` kill-switch. When false NOTHING is written or
   *  sent (no inbox row, no ledger claim, no push). */
  enabled: boolean;
  messaging: MessagingLike;
  nowMs: number;
  /** Live verification of an admin uid's CURRENT custom claim. */
  verifyAdmin: (uid: string) => Promise<boolean>;
}

export type NotifyOutcome =
  | "disabled"
  | "duplicate"
  | "cooling"
  | "inbox_only"
  | "skipped_pref"
  | "skipped_no_token"
  | "skipped_cap"
  | "sent"
  | "partial"
  | "failed";

export interface NotifyResult {
  outcome: NotifyOutcome;
  push?: PushResult;
}

// Per-instance sliding-window history for the per-recipient cap (plan §4.11).
// Deliberately in-memory: a best-effort loop brake, not a correctness
// mechanism - correctness is the deterministic ids above.
const capHistory = new Map<string, number[]>();

/** Test hook. */
export function resetRecipientCapHistory(): void {
  capHistory.clear();
}

function takeCap(recipient: string, nowMs: number): boolean {
  const r = evaluateRecipientCap(
    capHistory.get(recipient) ?? [],
    nowMs,
    RECIPIENT_PUSH_CAP,
    RECIPIENT_PUSH_WINDOW_MS,
  );
  capHistory.set(recipient, r.history);
  return r.allowed;
}

function logSend(type: string, result: PushResult): void {
  logger.info("notifications: push", summarizePushForLog(type, result));
}

export interface NotifyCustomerInput {
  uid: string;
  type: CustomerNotificationType;
  params: NotificationParams;
  /** Deterministic dedupe key == inbox doc id. */
  dedupeKey: string;
}

export async function notifyCustomer(
  input: NotifyCustomerInput,
  deps: NotifyDeps,
): Promise<NotifyResult> {
  if (!deps.enabled) return { outcome: "disabled" };

  const rendered = renderNotification(input.type, input.params);

  const written = await createInboxRow(input.uid, input.dedupeKey, rendered, deps.nowMs);
  if (written === "duplicate") return { outcome: "duplicate" };

  if (!rendered.pushes) {
    await setInboxPushOutcome(input.uid, input.dedupeKey, false, "inbox_only");
    return { outcome: "inbox_only" };
  }

  const prefs = await readPrefs(input.uid);
  if (
    !categoryAllowedForRole(rendered.category, "customer") ||
    !isPushEnabledByPrefs(rendered.category, prefs)
  ) {
    await setInboxPushOutcome(input.uid, input.dedupeKey, false, "skipped_pref");
    return { outcome: "skipped_pref" };
  }

  const devices = await tokensForUser(input.uid);
  // Only a customer-stamped token may receive customer pushes: a device that
  // is (still) registered under an admin role for this uid is not eligible.
  const tokens = devices.filter((d) => d.role === "customer").map((d) => d.token);
  if (tokens.length === 0) {
    await setInboxPushOutcome(input.uid, input.dedupeKey, false, "skipped_no_token");
    return { outcome: "skipped_no_token" };
  }

  if (!takeCap(input.uid, deps.nowMs)) {
    logger.warn("notifications: recipient cap reached - push dropped", { type: input.type });
    await setInboxPushOutcome(input.uid, input.dedupeKey, false, "skipped_cap");
    return { outcome: "skipped_cap" };
  }

  const data = buildPushData({
    rendered,
    recipientUid: input.uid,
    notificationId: input.dedupeKey,
  });
  const push = await sendPush({
    enabled: deps.enabled,
    messaging: deps.messaging,
    tokens,
    rendered,
    data,
  });
  logSend(input.type, push);
  await pruneDeviceTokens(push.pruneTokens).catch((err) =>
    logger.warn("notifications: token prune failed", { name: (err as { name?: unknown })?.name }),
  );
  await setInboxPushOutcome(
    input.uid,
    input.dedupeKey,
    push.ok > 0,
    push.outcome === "sent" ? "sent" : push.outcome === "partial" ? "partial" : "failed",
  );
  return { outcome: push.outcome === "sent" || push.outcome === "partial" ? push.outcome : "failed", push };
}

export interface NotifyAdminsInput {
  type: AdminNotificationType;
  params: NotificationParams;
  /** Ledger key (`adminKeys.*`). */
  dedupeKey: string;
  /** `null` = claim once; a number = re-claim after that many ms. */
  cooldownMs: number | null;
}

export async function notifyAdmins(
  input: NotifyAdminsInput,
  deps: NotifyDeps,
): Promise<NotifyResult> {
  if (!deps.enabled) return { outcome: "disabled" };

  const rendered = renderNotification(input.type, input.params);

  const claim = await claimAdminLedger(
    input.dedupeKey,
    input.type,
    rendered.entityId,
    deps.nowMs,
    input.cooldownMs,
  );
  if (claim === "duplicate") return { outcome: "duplicate" };
  if (claim === "cooling") return { outcome: "cooling" };

  const devices = await tokensForAdmins();
  const byUid = new Map<string, string[]>();
  for (const d of devices) {
    if (d.role !== "superAdmin") continue;
    byUid.set(d.uid, [...(byUid.get(d.uid) ?? []), d.token]);
  }

  const eligibleTokens: string[] = [];
  let sawPrefSkip = false;
  for (const [uid, tokens] of byUid) {
    let isAdmin = false;
    try {
      isAdmin = await deps.verifyAdmin(uid);
    } catch (err) {
      // Fail CLOSED: an admin push must never reach a uid we couldn't verify.
      logger.warn("notifications: admin verification failed - skipped", {
        name: (err as { name?: unknown })?.name,
      });
    }
    if (!isAdmin || !categoryAllowedForRole(rendered.category, "superAdmin")) continue;
    if (!isPushEnabledByPrefs(rendered.category, await readPrefs(uid))) {
      sawPrefSkip = true;
      continue;
    }
    if (!takeCap(uid, deps.nowMs)) {
      logger.warn("notifications: recipient cap reached - admin push dropped", {
        type: input.type,
      });
      continue;
    }
    eligibleTokens.push(...tokens);
  }

  if (eligibleTokens.length === 0) {
    return { outcome: sawPrefSkip ? "skipped_pref" : "skipped_no_token" };
  }

  const data = buildPushData({ rendered });
  const push = await sendPush({
    enabled: deps.enabled,
    messaging: deps.messaging,
    tokens: eligibleTokens,
    rendered,
    data,
  });
  logSend(input.type, push);
  await pruneDeviceTokens(push.pruneTokens).catch((err) =>
    logger.warn("notifications: token prune failed", { name: (err as { name?: unknown })?.name }),
  );
  return { outcome: push.outcome === "sent" || push.outcome === "partial" ? push.outcome : "failed", push };
}
