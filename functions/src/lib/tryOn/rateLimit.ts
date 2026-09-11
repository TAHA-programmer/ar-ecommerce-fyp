/**
 * Pure fixed-window rate-limit logic for `generateTryOn` (Phase 9.3 Stage 4,
 * developer decision D9): per-user 5/hour + 10/day, and a server-enforced
 * global 50/day circuit breaker. Both windows are evaluated and, only if
 * ALL of them still have room, bumped together - so a request that is
 * refused never partially consumes a cap. No dependency on Firestore; the
 * transaction in `reservation.ts` supplies the current window state read
 * from `tryOnQuota/{uid}` / `tryOnQuota/_global` and commits whatever this
 * module returns.
 */

export interface WindowState {
  windowStart: number;
  count: number;
}

/** Roll the window forward (reset to 0) if it has expired; otherwise keep it. */
export function currentWindow(
  state: WindowState | null | undefined,
  nowMs: number,
  windowMs: number,
): WindowState {
  if (!state || nowMs - state.windowStart >= windowMs) {
    return { windowStart: nowMs, count: 0 };
  }
  return state;
}

export interface UserQuotaState {
  hour: WindowState | null;
  day: WindowState | null;
}

export type UserQuotaVerdict =
  | { allowed: true; nextHour: WindowState; nextDay: WindowState }
  | { allowed: false; reason: "per_user_hourly" | "per_user_daily" };

export function evaluateUserQuota(
  state: UserQuotaState,
  nowMs: number,
  caps: { hourCap: number; hourWindowMs: number; dayCap: number; dayWindowMs: number },
): UserQuotaVerdict {
  const hour = currentWindow(state.hour, nowMs, caps.hourWindowMs);
  const day = currentWindow(state.day, nowMs, caps.dayWindowMs);

  if (hour.count >= caps.hourCap) {
    return { allowed: false, reason: "per_user_hourly" };
  }
  if (day.count >= caps.dayCap) {
    return { allowed: false, reason: "per_user_daily" };
  }
  return {
    allowed: true,
    nextHour: { windowStart: hour.windowStart, count: hour.count + 1 },
    nextDay: { windowStart: day.windowStart, count: day.count + 1 },
  };
}

export type GlobalQuotaVerdict =
  | { allowed: true; nextDay: WindowState }
  | { allowed: false; reason: "global_daily" };

export function evaluateGlobalQuota(
  state: WindowState | null,
  nowMs: number,
  caps: { dayCap: number; dayWindowMs: number },
): GlobalQuotaVerdict {
  const day = currentWindow(state, nowMs, caps.dayWindowMs);
  if (day.count >= caps.dayCap) {
    return { allowed: false, reason: "global_daily" };
  }
  return { allowed: true, nextDay: { windowStart: day.windowStart, count: day.count + 1 } };
}

/** Read a `WindowState` back out of a raw Firestore document map, or `null`. */
export function windowStateFromData(
  data: Record<string, unknown> | undefined,
  startKey: string,
  countKey: string,
  timestampToMillis: (v: unknown) => number | null,
): WindowState | null {
  if (!data) return null;
  const startMs = timestampToMillis(data[startKey]);
  const count = data[countKey];
  if (startMs === null || typeof count !== "number" || !Number.isFinite(count)) return null;
  return { windowStart: startMs, count: Math.max(0, Math.trunc(count)) };
}
