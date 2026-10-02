import { RECIPIENT_PUSH_CAP, RECIPIENT_PUSH_WINDOW_MS } from "./constants";

/**
 * Per-recipient push safety cap (plan §4.11): a sliding window that stops a
 * bug-driven loop from flooding one user. Pure - the caller (S3) persists
 * `history` however it likes (in-instance cache or a ledger doc).
 *
 * Returns whether this push is allowed and the pruned-and-updated history.
 * A dropped push is NOT recorded, so a flood can't extend its own block.
 */
export function evaluateRecipientCap(
  history: readonly number[],
  nowMs: number,
  max: number = RECIPIENT_PUSH_CAP,
  windowMs: number = RECIPIENT_PUSH_WINDOW_MS,
): { allowed: boolean; history: number[] } {
  const recent = history.filter(
    (t) => Number.isFinite(t) && t <= nowMs && nowMs - t < windowMs,
  );
  if (recent.length >= max) return { allowed: false, history: recent };
  return { allowed: true, history: [...recent, nowMs] };
}
