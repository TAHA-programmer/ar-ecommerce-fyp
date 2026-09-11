import { describe, expect, it } from "vitest";

import {
  currentWindow,
  evaluateGlobalQuota,
  evaluateUserQuota,
  windowStateFromData,
} from "../rateLimit";
import { timestampToMillis } from "../session";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const USER_CAPS = { hourCap: 5, hourWindowMs: HOUR_MS, dayCap: 10, dayWindowMs: DAY_MS };
const GLOBAL_CAPS = { dayCap: 50, dayWindowMs: DAY_MS };

describe("currentWindow", () => {
  it("starts a fresh window when there is no prior state", () => {
    expect(currentWindow(null, 1000, HOUR_MS)).toEqual({ windowStart: 1000, count: 0 });
  });

  it("keeps the window when still within it", () => {
    const state = { windowStart: 1000, count: 3 };
    expect(currentWindow(state, 1000 + HOUR_MS - 1, HOUR_MS)).toEqual(state);
  });

  it("resets once the window has elapsed", () => {
    const state = { windowStart: 1000, count: 3 };
    expect(currentWindow(state, 1000 + HOUR_MS, HOUR_MS)).toEqual({
      windowStart: 1000 + HOUR_MS,
      count: 0,
    });
  });
});

describe("evaluateUserQuota", () => {
  it("allows the first request and bumps both windows to 1", () => {
    const v = evaluateUserQuota({ hour: null, day: null }, 1000, USER_CAPS);
    expect(v).toEqual({
      allowed: true,
      nextHour: { windowStart: 1000, count: 1 },
      nextDay: { windowStart: 1000, count: 1 },
    });
  });

  it("allows up to the hourly cap, then refuses (per_user_hourly)", () => {
    const v = evaluateUserQuota(
      { hour: { windowStart: 1000, count: 5 }, day: { windowStart: 1000, count: 5 } },
      1500,
      USER_CAPS,
    );
    expect(v).toEqual({ allowed: false, reason: "per_user_hourly" });
  });

  it("allows up to the daily cap even under the hourly cap, then refuses (per_user_daily)", () => {
    const v = evaluateUserQuota(
      { hour: { windowStart: 1000, count: 1 }, day: { windowStart: 1000, count: 10 } },
      1500,
      USER_CAPS,
    );
    expect(v).toEqual({ allowed: false, reason: "per_user_daily" });
  });

  it("a rolled-over hour window resets the hourly count even if the day count is still high but under cap", () => {
    const v = evaluateUserQuota(
      { hour: { windowStart: 1000, count: 5 }, day: { windowStart: 1000, count: 9 } },
      1000 + HOUR_MS + 1,
      USER_CAPS,
    );
    expect(v.allowed).toBe(true);
    if (v.allowed) {
      expect(v.nextHour).toEqual({ windowStart: 1000 + HOUR_MS + 1, count: 1 });
      expect(v.nextDay).toEqual({ windowStart: 1000, count: 10 });
    }
  });

  it("a rolled-over day window resets both counts", () => {
    const v = evaluateUserQuota(
      { hour: { windowStart: 1000, count: 5 }, day: { windowStart: 1000, count: 10 } },
      1000 + DAY_MS + 1,
      USER_CAPS,
    );
    expect(v.allowed).toBe(true);
    if (v.allowed) {
      expect(v.nextHour).toEqual({ windowStart: 1000 + DAY_MS + 1, count: 1 });
      expect(v.nextDay).toEqual({ windowStart: 1000 + DAY_MS + 1, count: 1 });
    }
  });
});

describe("evaluateGlobalQuota", () => {
  it("allows the first request", () => {
    expect(evaluateGlobalQuota(null, 1000, GLOBAL_CAPS)).toEqual({
      allowed: true,
      nextDay: { windowStart: 1000, count: 1 },
    });
  });

  it("refuses once the global daily cap is reached (global_daily) - the real cost circuit breaker", () => {
    const v = evaluateGlobalQuota({ windowStart: 1000, count: 50 }, 1500, GLOBAL_CAPS);
    expect(v).toEqual({ allowed: false, reason: "global_daily" });
  });

  it("resets after the day window elapses", () => {
    const v = evaluateGlobalQuota({ windowStart: 1000, count: 50 }, 1000 + DAY_MS + 1, GLOBAL_CAPS);
    expect(v).toEqual({ allowed: true, nextDay: { windowStart: 1000 + DAY_MS + 1, count: 1 } });
  });
});

describe("windowStateFromData", () => {
  it("reads a well-formed window back out of a raw document map", () => {
    const data = { hourWindowStart: { toMillis: () => 1000 }, hourCount: 3 };
    expect(windowStateFromData(data, "hourWindowStart", "hourCount", timestampToMillis)).toEqual({
      windowStart: 1000,
      count: 3,
    });
  });

  it("returns null when the document is absent", () => {
    expect(windowStateFromData(undefined, "hourWindowStart", "hourCount", timestampToMillis)).toBeNull();
  });

  it("returns null for a missing/malformed timestamp or count (fails closed to a fresh window, never a negative/NaN count)", () => {
    expect(
      windowStateFromData({ hourCount: 3 }, "hourWindowStart", "hourCount", timestampToMillis),
    ).toBeNull();
    expect(
      windowStateFromData(
        { hourWindowStart: { toMillis: () => 1000 }, hourCount: "not a number" },
        "hourWindowStart",
        "hourCount",
        timestampToMillis,
      ),
    ).toBeNull();
  });

  it("clamps a corrupt negative count to 0 rather than letting it go negative", () => {
    expect(
      windowStateFromData(
        { hourWindowStart: { toMillis: () => 1000 }, hourCount: -5 },
        "hourWindowStart",
        "hourCount",
        timestampToMillis,
      ),
    ).toEqual({ windowStart: 1000, count: 0 });
  });
});
