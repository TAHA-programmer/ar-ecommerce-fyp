import type { MulticastMessage } from "firebase-admin/messaging";

import { FCM_MAX_TOKENS_PER_BATCH } from "./constants";
import { buildMulticastMessage } from "./payload";
import type { RenderedNotification } from "./types";

/**
 * Token fan-out with an injectable messaging seam (same idea as the Stripe /
 * Gemini fakes): production passes `getMessaging()`, tests pass a fake, so no
 * test ever contacts FCM. Pure apart from the injected call.
 */

export interface MessagingLike {
  sendEachForMulticast(message: MulticastMessage): Promise<{
    responses: ReadonlyArray<{ success: boolean; error?: { code?: string } }>;
  }>;
}

/** Per-token error codes that mean the token is permanently dead and its
 *  `deviceTokens` doc should be deleted. Anything else (unavailable,
 *  internal, quota, third-party-auth, invalid-argument = likely OUR payload)
 *  is NOT pruned - a transient or our-side failure must never delete a good
 *  device. */
const PRUNABLE_CODES: ReadonlySet<string> = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

export function isPrunableSendErrorCode(code: string | undefined): boolean {
  return code !== undefined && PRUNABLE_CODES.has(code);
}

export type PushOutcome =
  | "disabled" // kill-switch off: nothing attempted
  | "no_tokens"
  | "sent" // every token accepted
  | "partial" // some accepted, some failed
  | "failed"; // none accepted

export interface PushResult {
  outcome: PushOutcome;
  tried: number;
  ok: number;
  failed: number;
  /** Tokens whose docs must be deleted (dead tokens only). */
  pruneTokens: string[];
  /** Distinct per-token error codes seen (for logs; contains no tokens). */
  errorCodes: string[];
  /** Whole-batch transport failures (sendEachForMulticast threw). */
  batchErrors: number;
}

export interface SendPushInput {
  /** The `NOTIFICATIONS_ENABLED` kill-switch value (declared in S3). */
  enabled: boolean;
  messaging: MessagingLike;
  tokens: readonly string[];
  rendered: RenderedNotification;
  data: Record<string, string>;
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/**
 * Sends one notification to a set of device tokens. Never throws for FCM
 * failures: a thrown batch is counted (`batchErrors`) and its tokens are
 * counted failed but NOT pruned. Retrying a failed send is deliberately not
 * done here (decision D9: best-effort; the inbox is the guarantee).
 */
export async function sendPush(input: SendPushInput): Promise<PushResult> {
  const empty: PushResult = {
    outcome: "no_tokens",
    tried: 0,
    ok: 0,
    failed: 0,
    pruneTokens: [],
    errorCodes: [],
    batchErrors: 0,
  };
  if (!input.enabled) return { ...empty, outcome: "disabled" };

  const tokens = [...new Set(input.tokens.filter((t) => typeof t === "string" && t.length > 0))];
  if (tokens.length === 0) return empty;

  let ok = 0;
  let failed = 0;
  let batchErrors = 0;
  const prune = new Set<string>();
  const codes = new Set<string>();

  for (const batch of chunk(tokens, FCM_MAX_TOKENS_PER_BATCH)) {
    const message = buildMulticastMessage(batch, input.rendered, input.data);
    let response: Awaited<ReturnType<MessagingLike["sendEachForMulticast"]>>;
    try {
      response = await input.messaging.sendEachForMulticast(message);
    } catch {
      batchErrors += 1;
      failed += batch.length;
      continue;
    }
    batch.forEach((token, i) => {
      const r = response.responses[i];
      if (r?.success) {
        ok += 1;
        return;
      }
      failed += 1;
      const code = r?.error?.code;
      if (code) codes.add(code);
      if (isPrunableSendErrorCode(code)) prune.add(token);
    });
  }

  const outcome: PushOutcome = ok === 0 ? "failed" : failed === 0 ? "sent" : "partial";
  return {
    outcome,
    tried: tokens.length,
    ok,
    failed,
    pruneTokens: [...prune],
    errorCodes: [...codes].sort(),
    batchErrors,
  };
}

/** Log-safe summary: counts and error codes only - never a token, uid,
 *  email, address or amount. */
export function summarizePushForLog(
  type: string,
  result: PushResult,
): Record<string, string | number> {
  return {
    type,
    outcome: result.outcome,
    tried: result.tried,
    ok: result.ok,
    failed: result.failed,
    pruned: result.pruneTokens.length,
    batchErrors: result.batchErrors,
    errorCodes: result.errorCodes.join(","),
  };
}
