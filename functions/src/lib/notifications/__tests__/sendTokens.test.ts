import { describe, expect, it, vi } from "vitest";
import type { MulticastMessage } from "firebase-admin/messaging";

import {
  DeviceRegistrationValidationError,
  FCM_MAX_TOKENS_PER_BATCH,
  FCM_MESSAGE_TTL_MS,
  MAX_DEVICES_PER_USER,
  PushPayloadError,
  buildMulticastMessage,
  buildPushData,
  deviceTokenDocId,
  deviceTokenExpireAtMs,
  isPrunableSendErrorCode,
  parseRegisterDeviceRequest,
  parseUnregisterDeviceRequest,
  renderNotification,
  roleFromClaim,
  selectDevicesToEvict,
  sendPush,
  summarizePushForLog,
  type MessagingLike,
} from "..";

const ORDER_ID = "ord_0123456789abcdef0123456789abcdef01234567";
const tok = (n: number) => `fcm-token-${n}-`.padEnd(120, "x");

function fakeMessaging(
  respond: (m: MulticastMessage) => Array<{ success: boolean; code?: string }>,
): MessagingLike & { calls: MulticastMessage[] } {
  const calls: MulticastMessage[] = [];
  return {
    calls,
    async sendEachForMulticast(m) {
      calls.push(m);
      return {
        responses: respond(m).map((r) => ({
          success: r.success,
          error: r.code ? { code: r.code } : undefined,
        })),
      };
    },
  };
}

const rendered = renderNotification("order_shipped", { orderId: ORDER_ID });
const data = buildPushData({ rendered, recipientUid: "uid1", notificationId: "order_shipped_x" });

describe("buildPushData / buildMulticastMessage", () => {
  it("carries only allow-listed string fields and NO route/url", () => {
    expect(data).toEqual({
      v: "1",
      type: "order_shipped",
      audience: "customer",
      recipientUid: "uid1",
      orderId: ORDER_ID,
      notificationId: "order_shipped_x",
    });
    for (const v of Object.values(data)) expect(typeof v).toBe("string");
    expect(JSON.stringify(data)).not.toMatch(/route|http|\//i);
  });

  it("customer pushes require recipientUid; admin pushes carry none", () => {
    expect(() => buildPushData({ rendered })).toThrow(PushPayloadError);
    const admin = renderNotification("admin_low_stock", { productId: "p1", stockQuantity: 2 });
    const d = buildPushData({ rendered: admin });
    expect(d).toEqual({ v: "1", type: "admin_low_stock", audience: "admin", productId: "p1" });
    expect(d.recipientUid).toBeUndefined();
  });

  it("rejects ids that fail the shape check", () => {
    expect(() => buildPushData({ rendered, recipientUid: "a/b" })).toThrow(PushPayloadError);
    expect(() =>
      buildPushData({
        rendered: renderNotification("order_shipped", { orderId: "bad id" }),
        recipientUid: "u",
      }),
    ).toThrow(PushPayloadError);
  });

  it("builds an Android message with channel, tag, priority and a 24h ttl", () => {
    const m = buildMulticastMessage([tok(1)], rendered, data);
    expect(m.tokens).toEqual([tok(1)]);
    expect(m.notification).toEqual({ title: rendered.title, body: rendered.body });
    expect(m.android?.priority).toBe("high");
    expect(m.android?.ttl).toBe(FCM_MESSAGE_TTL_MS);
    expect(m.android?.notification).toEqual({ channelId: "orders", tag: ORDER_ID });
    expect(m.data).toBe(data);
  });

  it("review pushes use normal priority on the account channel", () => {
    const r = renderNotification("review_hidden", { reviewId: "u_p" });
    const m = buildMulticastMessage([tok(1)], r, buildPushData({ rendered: r, recipientUid: "u" }));
    expect(m.android?.priority).toBe("normal");
    expect(m.android?.notification?.channelId).toBe("account");
  });
});

describe("sendPush", () => {
  it("kill-switch off => nothing attempted", async () => {
    const messaging = fakeMessaging(() => []);
    const r = await sendPush({ enabled: false, messaging, tokens: [tok(1)], rendered, data });
    expect(r.outcome).toBe("disabled");
    expect(messaging.calls.length).toBe(0);
  });

  it("no tokens => no_tokens and no call; blanks/duplicates are dropped", async () => {
    const messaging = fakeMessaging((m) => m.tokens.map(() => ({ success: true })));
    const none = await sendPush({ enabled: true, messaging, tokens: [], rendered, data });
    expect(none.outcome).toBe("no_tokens");
    expect(messaging.calls.length).toBe(0);

    const r = await sendPush({
      enabled: true,
      messaging,
      tokens: [tok(1), tok(1), "", tok(2)],
      rendered,
      data,
    });
    expect(r.tried).toBe(2);
    expect(r.outcome).toBe("sent");
    expect(messaging.calls[0].tokens).toEqual([tok(1), tok(2)]);
  });

  it("prunes only dead tokens; keeps tokens that failed transiently", async () => {
    const tokens = [tok(1), tok(2), tok(3), tok(4), tok(5)];
    const messaging = fakeMessaging(() => [
      { success: true },
      { success: false, code: "messaging/registration-token-not-registered" },
      { success: false, code: "messaging/invalid-registration-token" },
      { success: false, code: "messaging/unavailable" },
      { success: false, code: "messaging/invalid-argument" },
    ]);
    const r = await sendPush({ enabled: true, messaging, tokens, rendered, data });
    expect(r.outcome).toBe("partial");
    expect(r).toMatchObject({ tried: 5, ok: 1, failed: 4 });
    expect(r.pruneTokens.sort()).toEqual([tok(2), tok(3)].sort());
    expect(r.errorCodes).toEqual([
      "messaging/invalid-argument",
      "messaging/invalid-registration-token",
      "messaging/registration-token-not-registered",
      "messaging/unavailable",
    ]);
  });

  it("all failed => failed; a thrown batch is counted, not thrown, not pruned", async () => {
    const throwing: MessagingLike = {
      sendEachForMulticast: vi.fn().mockRejectedValue(new Error("network down")),
    };
    const r = await sendPush({
      enabled: true,
      messaging: throwing,
      tokens: [tok(1), tok(2)],
      rendered,
      data,
    });
    expect(r.outcome).toBe("failed");
    expect(r).toMatchObject({ tried: 2, ok: 0, failed: 2, batchErrors: 1 });
    expect(r.pruneTokens).toEqual([]);
  });

  it("chunks at the 500-token FCM limit and continues past a failed chunk", async () => {
    const tokens = Array.from({ length: FCM_MAX_TOKENS_PER_BATCH + 7 }, (_, i) => tok(i));
    let n = 0;
    const messaging: MessagingLike & { sizes: number[] } = {
      sizes: [],
      async sendEachForMulticast(m) {
        this.sizes.push(m.tokens.length);
        if (n++ === 0) throw new Error("first chunk fails");
        return { responses: m.tokens.map(() => ({ success: true })) };
      },
    };
    const r = await sendPush({ enabled: true, messaging, tokens, rendered, data });
    expect(messaging.sizes).toEqual([FCM_MAX_TOKENS_PER_BATCH, 7]);
    expect(r).toMatchObject({ tried: 507, ok: 7, failed: 500, batchErrors: 1, outcome: "partial" });
  });

  it("a short response array never crashes (missing entries count as failed)", async () => {
    const messaging = fakeMessaging(() => [{ success: true }]);
    const r = await sendPush({
      enabled: true,
      messaging,
      tokens: [tok(1), tok(2)],
      rendered,
      data,
    });
    expect(r).toMatchObject({ ok: 1, failed: 1, outcome: "partial" });
    expect(r.pruneTokens).toEqual([]);
  });

  it("log summary contains no token, uid or order id", async () => {
    const messaging = fakeMessaging(() => [
      { success: false, code: "messaging/registration-token-not-registered" },
    ]);
    const r = await sendPush({ enabled: true, messaging, tokens: [tok(1)], rendered, data });
    const log = JSON.stringify(summarizePushForLog("order_shipped", r));
    expect(log).not.toContain(tok(1));
    expect(log).not.toContain("uid1");
    expect(log).not.toContain(ORDER_ID);
    expect(log).toContain("registration-token-not-registered");
  });
});

describe("isPrunableSendErrorCode", () => {
  it("is true for exactly the two dead-token codes", () => {
    expect(isPrunableSendErrorCode("messaging/registration-token-not-registered")).toBe(true);
    expect(isPrunableSendErrorCode("messaging/invalid-registration-token")).toBe(true);
    for (const c of [
      "messaging/invalid-argument",
      "messaging/unavailable",
      "messaging/internal-error",
      "messaging/server-unavailable",
      "messaging/message-rate-exceeded",
      "messaging/third-party-auth-error",
      undefined,
      "",
    ]) {
      expect(isPrunableSendErrorCode(c)).toBe(false);
    }
  });
});

describe("registerDevice validation", () => {
  const valid = { token: tok(1), platform: "android", appVersion: "1.0.0+1", installId: "inst-abc" };

  it("accepts a well-formed request and copies only known fields", () => {
    const r = parseRegisterDeviceRequest({ ...valid, role: "superAdmin", uid: "evil" });
    expect(r).toEqual(valid);
    expect(r).not.toHaveProperty("role");
    expect(r).not.toHaveProperty("uid");
  });

  it("rejects bad shapes", () => {
    const bad: unknown[] = [
      null,
      "x",
      [],
      { ...valid, token: "short" },
      { ...valid, token: "x".repeat(4097) },
      { ...valid, token: `${tok(1)}/slash` },
      { ...valid, token: 12 },
      { ...valid, platform: "ios" },
      { ...valid, appVersion: "" },
      { ...valid, appVersion: "v".repeat(33) },
      { ...valid, appVersion: "1.0<script>" },
      { ...valid, installId: "" },
      { ...valid, installId: "i".repeat(65) },
      { ...valid, installId: "a/b" },
    ];
    for (const b of bad) {
      expect(() => parseRegisterDeviceRequest(b)).toThrow(DeviceRegistrationValidationError);
    }
  });

  it("unregister requires only a valid token", () => {
    expect(parseUnregisterDeviceRequest({ token: tok(2) })).toEqual({ token: tok(2) });
    expect(() => parseUnregisterDeviceRequest({})).toThrow(DeviceRegistrationValidationError);
    expect(() => parseUnregisterDeviceRequest({ token: "nope" })).toThrow(
      DeviceRegistrationValidationError,
    );
  });
});

describe("token identity, role and eviction", () => {
  it("doc id is a stable sha256 hex that never contains the token", () => {
    const id = deviceTokenDocId(tok(1));
    expect(id).toMatch(/^[0-9a-f]{64}$/);
    expect(id).toBe(deviceTokenDocId(tok(1)));
    expect(id).not.toBe(deviceTokenDocId(tok(2)));
    expect(id).not.toContain("fcm-token");
  });

  it("role comes only from the exact superAdmin claim", () => {
    expect(roleFromClaim("superAdmin")).toBe("superAdmin");
    for (const c of [undefined, null, "customer", "SuperAdmin", "admin", true, 1, {}]) {
      expect(roleFromClaim(c)).toBe("customer");
    }
  });

  it("evicts the oldest devices beyond the cap and never the one being registered", () => {
    const devices = Array.from({ length: MAX_DEVICES_PER_USER }, (_, i) => ({
      id: `d${i}`,
      lastSeenMs: 1000 + i,
    }));
    // registering a NEW (11th) device evicts the single oldest
    expect(selectDevicesToEvict(devices, "new")).toEqual(["d0"]);
    // re-registering an existing device at the cap evicts nothing
    expect(selectDevicesToEvict(devices, "d3")).toEqual([]);
    // keepId is never evicted even if it is the oldest
    expect(selectDevicesToEvict([...devices, { id: "new", lastSeenMs: 1 }], "new")).toEqual(["d0"]);
    expect(selectDevicesToEvict(devices.slice(0, 3), "new")).toEqual([]);
  });

  it("evicts several when far over the cap, oldest first, deterministic on ties", () => {
    const devices = Array.from({ length: 13 }, (_, i) => ({ id: `d${i}`, lastSeenMs: 5 }));
    const out = selectDevicesToEvict(devices, "d12", 10);
    expect(out).toEqual(["d0", "d1", "d10"]); // string order on ties; 13 others-1 => 12+1-10=3
  });

  it("expireAt is now + 60 days", () => {
    expect(deviceTokenExpireAtMs(1000)).toBe(1000 + 60 * 24 * 60 * 60 * 1000);
  });
});
