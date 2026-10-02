import { beforeEach, describe, expect, it } from "vitest";
import type { MulticastMessage } from "firebase-admin/messaging";
import { Timestamp } from "firebase-admin/firestore";

import {
  cleanupNotificationDataForUser,
  registerDeviceHandler,
  unregisterDeviceHandler,
} from "../src/lib/notifications/devices";
import { notifyAdmins, notifyCustomer, resetRecipientCapHistory } from "../src/lib/notifications/notify";
import type { NotifyDeps } from "../src/lib/notifications/notify";
import {
  handleOrderCreated,
  handleOrderStatusChange,
  handleProductStockChange,
  handleReviewChange,
  handleStripeEventCreated,
} from "../src/lib/notifications/triggers";
import {
  DEVICE_TOKEN_TTL_MS,
  INBOX_TTL_MS,
  LOW_STOCK_COOLDOWN_MS,
  MAX_DEVICES_PER_USER,
  RECIPIENT_PUSH_CAP,
  deviceTokenDocId,
  type MessagingLike,
} from "../src/lib/notifications";
import { clearFirestore, testDb } from "./helpers/emulator";

const ALICE = "alice";
const BOB = "bob";
const ADMIN = "admin-uid";
const ORDER_ID = "ord_0123456789abcdef0123456789abcdef01234567";
const NOW = 1_800_000_000_000;

const tok = (n: number | string) => `fcm-token-${n}-`.padEnd(140, "x");

interface Fake extends MessagingLike {
  calls: MulticastMessage[];
  failWith: Map<string, string>;
}

function fakeMessaging(): Fake {
  const f: Fake = {
    calls: [],
    failWith: new Map(),
    async sendEachForMulticast(m) {
      f.calls.push(m);
      return {
        responses: m.tokens.map((t) => {
          const code = f.failWith.get(t);
          return code ? { success: false, error: { code } } : { success: true };
        }),
      };
    },
  };
  return f;
}

function deps(
  messaging: MessagingLike,
  over: Partial<NotifyDeps> = {},
): NotifyDeps {
  return {
    enabled: true,
    messaging,
    nowMs: NOW,
    verifyAdmin: async (uid) => uid === ADMIN,
    ...over,
  };
}

async function register(uid: string, role: string | undefined, token: string, installId = "inst", nowMs = NOW) {
  return registerDeviceHandler({
    authUid: uid,
    authRole: role,
    data: { token, platform: "android", appVersion: "1.0.0+1", installId },
    nowMs,
  });
}

async function inbox(uid: string) {
  const snap = await testDb.collection(`users/${uid}/notifications`).get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function tokenDocs(uid?: string) {
  const col = testDb.collection("deviceTokens");
  const snap = uid ? await col.where("uid", "==", uid).get() : await col.get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() })) as Array<Record<string, unknown> & { id: string }>;
}

beforeEach(async () => {
  await clearFirestore();
  resetRecipientCapHistory();
});

// ---------------------------------------------------------------------------
describe("registerDevice / unregisterDevice", () => {
  it("rejects unauthenticated and malformed requests", async () => {
    await expect(
      registerDeviceHandler({ authUid: undefined, authRole: undefined, data: {}, nowMs: NOW }),
    ).rejects.toMatchObject({ code: "unauthenticated" });
    await expect(
      registerDeviceHandler({ authUid: ALICE, authRole: undefined, data: { token: "short" }, nowMs: NOW }),
    ).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(unregisterDeviceHandler({ authUid: undefined, data: {} })).rejects.toMatchObject({
      code: "unauthenticated",
    });
    expect(await tokenDocs()).toHaveLength(0);
  });

  it("stores the token under sha256(token) with the role from the VERIFIED claim, never the body", async () => {
    await registerDeviceHandler({
      authUid: ALICE,
      authRole: undefined, // no claim => customer
      data: {
        token: tok(1),
        platform: "android",
        appVersion: "1.0.0+1",
        installId: "inst",
        role: "superAdmin", // forged - must be ignored
        uid: BOB,
      },
      nowMs: NOW,
    });
    const docs = await tokenDocs();
    expect(docs).toHaveLength(1);
    expect(docs[0].id).toBe(deviceTokenDocId(tok(1)));
    expect(docs[0]).toMatchObject({ uid: ALICE, role: "customer", token: tok(1), platform: "android" });
    expect((docs[0].expireAt as Timestamp).toMillis()).toBe(NOW + DEVICE_TOKEN_TTL_MS);

    await register(ADMIN, "superAdmin", tok(2), "inst-admin");
    const admin = (await tokenDocs(ADMIN))[0];
    expect(admin.role).toBe("superAdmin");
  });

  it("re-registering the same token refreshes lastSeenAt and keeps createdAt", async () => {
    await register(ALICE, undefined, tok(1), "inst", NOW);
    await register(ALICE, undefined, tok(1), "inst", NOW + 7 * 86_400_000);
    const docs = await tokenDocs(ALICE);
    expect(docs).toHaveLength(1);
    expect((docs[0].createdAt as Timestamp).toMillis()).toBe(NOW);
    expect((docs[0].lastSeenAt as Timestamp).toMillis()).toBe(NOW + 7 * 86_400_000);
  });

  it("MOVES ownership when another account registers the same token (shared device)", async () => {
    await register(ALICE, undefined, tok(1), "inst-a");
    await register(BOB, undefined, tok(1), "inst-b");
    expect(await tokenDocs(ALICE)).toHaveLength(0);
    const bob = await tokenDocs(BOB);
    expect(bob).toHaveLength(1);
    expect(bob[0].id).toBe(deviceTokenDocId(tok(1)));
  });

  it("a refreshed token from the same install replaces the old one", async () => {
    await register(ALICE, undefined, tok("old"), "inst-1", NOW);
    await register(ALICE, undefined, tok("new"), "inst-1", NOW + 1000);
    const docs = await tokenDocs(ALICE);
    expect(docs.map((d) => d.token)).toEqual([tok("new")]);
  });

  it("caps a user at MAX_DEVICES_PER_USER, evicting the oldest lastSeenAt", async () => {
    for (let i = 0; i < MAX_DEVICES_PER_USER + 1; i++) {
      await register(ALICE, undefined, tok(i), `inst-${i}`, NOW + i * 1000);
    }
    const docs = await tokenDocs(ALICE);
    expect(docs).toHaveLength(MAX_DEVICES_PER_USER);
    const tokens = docs.map((d) => d.token);
    expect(tokens).not.toContain(tok(0)); // oldest evicted
    expect(tokens).toContain(tok(MAX_DEVICES_PER_USER)); // newest kept
  });

  it("unregister removes only the caller's OWN token and is idempotent", async () => {
    await register(ALICE, undefined, tok(1), "inst-a");
    expect(await unregisterDeviceHandler({ authUid: BOB, data: { token: tok(1) } })).toEqual({
      removed: false,
    });
    expect(await tokenDocs(ALICE)).toHaveLength(1);
    expect(await unregisterDeviceHandler({ authUid: ALICE, data: { token: tok(1) } })).toEqual({
      removed: true,
    });
    expect(await unregisterDeviceHandler({ authUid: ALICE, data: { token: tok(1) } })).toEqual({
      removed: false,
    });
    expect(await tokenDocs()).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
describe("customer notifications (order status)", () => {
  const confirmed = { orderStatus: "confirmed", userId: ALICE };
  const pending = { orderStatus: "pending", userId: ALICE };

  it("kill-switch OFF: no inbox row, no ledger claim, no push", async () => {
    await register(ALICE, undefined, tok(1));
    const m = fakeMessaging();
    const r = await handleOrderStatusChange(ORDER_ID, pending, confirmed, deps(m, { enabled: false }));
    expect(r.map((x) => x.outcome)).toEqual(["disabled"]);
    expect(await inbox(ALICE)).toHaveLength(0);
    expect(m.calls).toHaveLength(0);

    const a = await handleOrderCreated(ORDER_ID, { userId: ALICE }, deps(m, { enabled: false }));
    expect(a.map((x) => x.outcome)).toEqual(["disabled", "disabled"]);
    expect((await testDb.collection("notificationEvents").get()).size).toBe(0);
  });

  it("writes the inbox row (readAt null, TTL) and pushes with channel/tag/priority to customer tokens only", async () => {
    await register(ALICE, undefined, tok(1), "inst-a");
    await register(ALICE, "superAdmin", tok(2), "inst-b"); // admin-stamped token must NOT get a customer push
    const m = fakeMessaging();
    const [res] = await handleOrderStatusChange(ORDER_ID, pending, confirmed, deps(m));
    expect(res.outcome).toBe("sent");

    const rows = await inbox(ALICE);
    expect(rows).toHaveLength(1);
    expect(rows[0].id).toBe(`order_confirmed_${ORDER_ID}`);
    expect(rows[0]).toMatchObject({
      type: "order_confirmed",
      route: "orderDetail",
      entityId: ORDER_ID,
      readAt: null,
      pushed: true,
      pushOutcome: "sent",
    });
    expect((rows[0] as unknown as { expireAt: Timestamp }).expireAt.toMillis()).toBe(NOW + INBOX_TTL_MS);

    expect(m.calls).toHaveLength(1);
    expect(m.calls[0].tokens).toEqual([tok(1)]);
    expect(m.calls[0].android?.notification).toEqual({ channelId: "orders", tag: ORDER_ID });
    expect(m.calls[0].android?.priority).toBe("high");
    expect(m.calls[0].data).toMatchObject({
      v: "1",
      type: "order_confirmed",
      audience: "customer",
      recipientUid: ALICE,
      orderId: ORDER_ID,
      notificationId: `order_confirmed_${ORDER_ID}`,
    });
  });

  it("a replayed (duplicate) trigger delivery sends NOTHING more", async () => {
    await register(ALICE, undefined, tok(1));
    const m = fakeMessaging();
    await handleOrderStatusChange(ORDER_ID, pending, confirmed, deps(m));
    const again = await handleOrderStatusChange(ORDER_ID, pending, confirmed, deps(m));
    expect(again.map((x) => x.outcome)).toEqual(["duplicate"]);
    expect(m.calls).toHaveLength(1);
    expect(await inbox(ALICE)).toHaveLength(1);
  });

  it("confirmed -> shipped -> delivered yields one row each; cancellation too; no-ops yield none", async () => {
    await register(ALICE, undefined, tok(1));
    const m = fakeMessaging();
    const o = (orderStatus: string) => ({ orderStatus, userId: ALICE });
    await handleOrderStatusChange(ORDER_ID, o("pending"), o("confirmed"), deps(m));
    await handleOrderStatusChange(ORDER_ID, o("confirmed"), o("shipped"), deps(m));
    await handleOrderStatusChange(ORDER_ID, o("shipped"), o("delivered"), deps(m));
    expect((await inbox(ALICE)).map((r) => r.id).sort()).toEqual(
      [`order_confirmed_${ORDER_ID}`, `order_delivered_${ORDER_ID}`, `order_shipped_${ORDER_ID}`].sort(),
    );
    expect(await handleOrderStatusChange(ORDER_ID, o("shipped"), o("shipped"), deps(m))).toEqual([]);
    expect(await handleOrderStatusChange(ORDER_ID, o("confirmed"), o("pending"), deps(m))).toEqual([]);
    await handleOrderStatusChange(ORDER_ID + "2", o("confirmed"), o("cancelled"), deps(m));
    const cancelled = (await inbox(ALICE)).find((r) => r.id === `order_cancelled_${ORDER_ID}2`);
    expect(cancelled).toBeDefined();
    expect(String((cancelled as unknown as { body: string }).body).toLowerCase()).not.toContain("refund");
    expect(m.calls).toHaveLength(4);
    // every push for one order shares the tag so the tray entry is replaced
    expect(new Set(m.calls.slice(0, 3).map((c) => c.android?.notification?.tag)).size).toBe(1);
  });

  it("D7: pushOrders=false suppresses the push but the inbox STILL records the event", async () => {
    await register(ALICE, undefined, tok(1));
    await testDb.doc(`users/${ALICE}/notificationSettings/prefs`).set({ pushOrders: false });
    const m = fakeMessaging();
    const [r] = await handleOrderStatusChange(ORDER_ID, pending, confirmed, deps(m));
    expect(r.outcome).toBe("skipped_pref");
    expect(m.calls).toHaveLength(0);
    const rows = await inbox(ALICE);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ pushed: false, pushOutcome: "skipped_pref", readAt: null });
  });

  it("missing/corrupt prefs default ON; only an explicit false mutes", async () => {
    await register(ALICE, undefined, tok(1));
    await testDb.doc(`users/${ALICE}/notificationSettings/prefs`).set({ pushOrders: "no", pushReviews: false });
    const m = fakeMessaging();
    const [r] = await handleOrderStatusChange(ORDER_ID, pending, confirmed, deps(m));
    expect(r.outcome).toBe("sent"); // reviews switch is irrelevant to orders
  });

  it("no registered device: inbox row written, outcome skipped_no_token", async () => {
    const m = fakeMessaging();
    const [r] = await handleOrderStatusChange(ORDER_ID, pending, confirmed, deps(m));
    expect(r.outcome).toBe("skipped_no_token");
    expect((await inbox(ALICE))[0]).toMatchObject({ pushed: false, pushOutcome: "skipped_no_token" });
    expect(m.calls).toHaveLength(0);
  });

  it("prunes ONLY dead tokens; transient failures keep the device", async () => {
    await register(ALICE, undefined, tok("good"), "i1");
    await register(ALICE, undefined, tok("dead"), "i2");
    await register(ALICE, undefined, tok("flaky"), "i3");
    const m = fakeMessaging();
    m.failWith.set(tok("dead"), "messaging/registration-token-not-registered");
    m.failWith.set(tok("flaky"), "messaging/unavailable");
    const [r] = await handleOrderStatusChange(ORDER_ID, pending, confirmed, deps(m));
    expect(r.outcome).toBe("partial");
    const left = (await tokenDocs(ALICE)).map((d) => d.token).sort();
    expect(left).toEqual([tok("flaky"), tok("good")].sort());
    expect((await inbox(ALICE))[0]).toMatchObject({ pushed: true, pushOutcome: "partial" });
  });

  it("all tokens failing transiently: push marked failed, nothing pruned, no throw", async () => {
    await register(ALICE, undefined, tok(1));
    const m = fakeMessaging();
    m.failWith.set(tok(1), "messaging/internal-error");
    const [r] = await handleOrderStatusChange(ORDER_ID, pending, confirmed, deps(m));
    expect(r.outcome).toBe("failed");
    expect(await tokenDocs(ALICE)).toHaveLength(1);
    expect((await inbox(ALICE))[0]).toMatchObject({ pushed: false, pushOutcome: "failed" });
  });

  it("per-recipient cap drops pushes beyond the limit but still records the inbox", async () => {
    await register(ALICE, undefined, tok(1));
    const m = fakeMessaging();
    let last = "";
    for (let i = 0; i <= RECIPIENT_PUSH_CAP; i++) {
      const [r] = await notifyCustomer(
        {
          uid: ALICE,
          type: "order_shipped",
          params: { orderId: `ord_${i}` },
          dedupeKey: `order_shipped_ord_${i}`,
        },
        deps(m),
      ).then((x) => [x]);
      last = r.outcome;
    }
    expect(last).toBe("skipped_cap");
    expect(m.calls).toHaveLength(RECIPIENT_PUSH_CAP);
    expect(await inbox(ALICE)).toHaveLength(RECIPIENT_PUSH_CAP + 1);
  });

  it("order_placed is inbox-only (never pushes) and also raises the admin 'new order' alert", async () => {
    await register(ALICE, undefined, tok("c"), "ic");
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    const m = fakeMessaging();
    const r = await handleOrderCreated(ORDER_ID, { userId: ALICE }, deps(m));
    expect(r.map((x) => x.outcome)).toEqual(["sent", "inbox_only"]);
    expect(m.calls).toHaveLength(1);
    expect(m.calls[0].tokens).toEqual([tok("a")]);
    expect(m.calls[0].data).toMatchObject({ audience: "admin", type: "admin_new_order", orderId: ORDER_ID });
    expect(m.calls[0].data?.recipientUid).toBeUndefined();
    expect((await inbox(ALICE))[0]).toMatchObject({ type: "order_placed", pushed: false, pushOutcome: "inbox_only" });
    // replay: both duplicates
    const again = await handleOrderCreated(ORDER_ID, { userId: ALICE }, deps(m));
    expect(again.map((x) => x.outcome)).toEqual(["duplicate", "duplicate"]);
    expect(m.calls).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
describe("admin notifications", () => {
  it("sends only to verified-current admins; a demoted/unverifiable token holder is skipped (fail closed)", async () => {
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    await register("demoted", "superAdmin", tok("d"), "id"); // stale stamped role
    await register("broken", "superAdmin", tok("b"), "ib"); // verification throws
    const m = fakeMessaging();
    const r = await handleOrderCreated(
      ORDER_ID,
      {},
      deps(m, {
        verifyAdmin: async (uid) => {
          if (uid === "broken") throw new Error("auth outage");
          return uid === ADMIN;
        },
      }),
    );
    expect(r[0].outcome).toBe("sent");
    expect(m.calls[0].tokens).toEqual([tok("a")]);
  });

  it("customers with admin-looking prefs/tokens never receive admin alerts", async () => {
    await register(ALICE, undefined, tok("c"), "ic");
    const m = fakeMessaging();
    const [r] = await handleOrderCreated(ORDER_ID, {}, deps(m));
    expect(r.outcome).toBe("skipped_no_token");
    expect(m.calls).toHaveLength(0);
  });

  it("admin category switch off => skipped_pref (ledger still claimed)", async () => {
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    await testDb.doc(`users/${ADMIN}/notificationSettings/prefs`).set({ pushAdminOrders: false });
    const m = fakeMessaging();
    const [r] = await handleOrderCreated(ORDER_ID, {}, deps(m));
    expect(r.outcome).toBe("skipped_pref");
    expect(m.calls).toHaveLength(0);
    expect((await testDb.collection("notificationEvents").get()).size).toBe(1);
  });

  it("low stock: fires on crossing, collapses flapping inside the 6h cooldown, re-fires after it", async () => {
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    const m = fakeMessaging();
    const prod = (n: number) => ({ title: "Luna Chair", stockQuantity: n });

    const first = await handleProductStockChange("p1", prod(6), prod(5), deps(m, { nowMs: NOW }));
    expect(first[0].outcome).toBe("sent");
    expect(m.calls[0].notification?.body).toBe("Luna Chair: 5 left.");
    expect(m.calls[0].android?.notification).toMatchObject({ channelId: "admin_stock", tag: "admin_stock_p1" });

    // reserve -> restore -> reserve around the boundary, 1 minute later
    const flap = await handleProductStockChange("p1", prod(6), prod(5), deps(m, { nowMs: NOW + 60_000 }));
    expect(flap[0].outcome).toBe("cooling");
    expect(m.calls).toHaveLength(1);

    const later = await handleProductStockChange(
      "p1",
      prod(6),
      prod(4),
      deps(m, { nowMs: NOW + LOW_STOCK_COOLDOWN_MS + 1 }),
    );
    expect(later[0].outcome).toBe("sent");
    expect(m.calls).toHaveLength(2);
    const ledger = (await testDb.doc("notificationEvents/admin_lowstock_p1").get()).data();
    expect(ledger?.count).toBe(2);
  });

  it("out of stock fires on >0 -> 0 with its own key; non-crossing changes do nothing", async () => {
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    const m = fakeMessaging();
    const prod = (n: number) => ({ title: "Luna Chair", stockQuantity: n });
    expect(await handleProductStockChange("p1", prod(4), prod(3), deps(m))).toEqual([]);
    expect(await handleProductStockChange("p1", prod(0), prod(8), deps(m))).toEqual([]);
    const [r] = await handleProductStockChange("p1", prod(2), prod(0), deps(m));
    expect(r.outcome).toBe("sent");
    expect(m.calls[0].notification?.title).toBe("Out of stock");
    expect((await testDb.doc("notificationEvents/admin_oos_p1").get()).exists).toBe(true);
  });

  it("an unreadable stock quantity never raises an alert", async () => {
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    const m = fakeMessaging();
    expect(
      await handleProductStockChange("p1", { stockQuantity: 6 }, { stockQuantity: "oops" }, deps(m)),
    ).toEqual([]);
    expect(m.calls).toHaveLength(0);
  });

  it("direct notifyAdmins claim-once semantics (duplicate on replay)", async () => {
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    const m = fakeMessaging();
    const input = {
      type: "admin_review_flagged" as const,
      params: { reviewId: "u_p" },
      dedupeKey: "admin_flag_u_p",
      cooldownMs: null,
    };
    expect((await notifyAdmins(input, deps(m))).outcome).toBe("sent");
    expect((await notifyAdmins(input, deps(m))).outcome).toBe("duplicate");
    expect(m.calls).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
describe("review notifications", () => {
  const base = { userId: ALICE, status: "published", flaggedForReview: false, moderatedBy: null, moderatedAt: null };
  const ts = (ms: number) => Timestamp.fromMillis(ms);
  const REVIEW_ID = `${ALICE}_p1`;

  it("admin hide notifies the author (low-priority account channel, generic copy); replay is a duplicate", async () => {
    await register(ALICE, undefined, tok(1));
    const m = fakeMessaging();
    const after = { ...base, status: "hidden", moderatedBy: ADMIN, moderatedAt: ts(NOW - 5000), moderationReason: "spam words" };
    const [r] = await handleReviewChange(REVIEW_ID, base, after, deps(m));
    expect(r.outcome).toBe("sent");
    expect(m.calls[0].android).toMatchObject({ priority: "normal" });
    expect(m.calls[0].android?.notification?.channelId).toBe("account");
    const text = `${m.calls[0].notification?.title} ${m.calls[0].notification?.body}`;
    expect(text).not.toMatch(/spam|reason/i);
    const rows = await inbox(ALICE);
    expect(rows[0].id).toBe(`review_hidden_${REVIEW_ID}_${NOW - 5000}`);
    const again = await handleReviewChange(REVIEW_ID, base, after, deps(m));
    expect(again[0].outcome).toBe("duplicate");
    expect(m.calls).toHaveLength(1);
  });

  it("restored is inbox-only; the pushReviews switch mutes hidden pushes but not the inbox", async () => {
    await register(ALICE, undefined, tok(1));
    await testDb.doc(`users/${ALICE}/notificationSettings/prefs`).set({ pushReviews: false });
    const m = fakeMessaging();
    const hidden = { ...base, status: "hidden", moderatedBy: ADMIN, moderatedAt: ts(1_000) };
    const [a] = await handleReviewChange(REVIEW_ID, base, hidden, deps(m));
    expect(a.outcome).toBe("skipped_pref");
    const restored = { ...hidden, status: "published", moderatedAt: ts(2_000) };
    const [b] = await handleReviewChange(REVIEW_ID, hidden, restored, deps(m));
    expect(b.outcome).toBe("inbox_only");
    expect(await inbox(ALICE)).toHaveLength(2);
    expect(m.calls).toHaveLength(0);
  });

  it("an author's own edit/re-publish (moderatedBy reset) NEVER notifies", async () => {
    await register(ALICE, undefined, tok(1));
    const m = fakeMessaging();
    const moderated = { ...base, status: "hidden", moderatedBy: ADMIN, moderatedAt: ts(5_000) };
    const edited = { ...base, status: "published", moderatedBy: null, moderatedAt: null };
    expect(await handleReviewChange(REVIEW_ID, moderated, edited, deps(m))).toEqual([]);
    expect(await inbox(ALICE)).toHaveLength(0);
    expect(m.calls).toHaveLength(0);
  });

  it("flagged -> admin alert once", async () => {
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    const m = fakeMessaging();
    const flagged = { ...base, flaggedForReview: true };
    const [r] = await handleReviewChange(REVIEW_ID, base, flagged, deps(m));
    expect(r.outcome).toBe("sent");
    expect(m.calls[0].data).toMatchObject({ type: "admin_review_flagged", reviewId: REVIEW_ID });
    expect((await handleReviewChange(REVIEW_ID, base, flagged, deps(m)))[0].outcome).toBe("duplicate");
  });
});

// ---------------------------------------------------------------------------
describe("stripe ledger events (refund / anomaly)", () => {
  const record = (outcome: string, extra: Record<string, unknown> = {}) => ({
    outcome,
    paymentIntentId: "pi_123",
    checkoutSessionId: "sess1",
    ...extra,
  });

  it("refund: customer notice resolved via the checkout session owner + admin payment issue", async () => {
    await testDb.doc("checkoutSessions/sess1").set({ userId: ALICE, status: "expired" });
    await register(ALICE, undefined, tok("c"), "ic");
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    const m = fakeMessaging();
    const r = await handleStripeEventCreated("evt_1", record("refunded_reservation_lost:expired"), deps(m));
    expect(r.map((x) => x.outcome)).toEqual(["sent", "sent"]);
    const rows = await inbox(ALICE);
    expect(rows[0]).toMatchObject({ id: "refund_pi_123", type: "payment_refunded", route: "orders", entityId: null });
    const customerPush = m.calls.find((c) => c.data?.audience === "customer");
    expect(customerPush?.tokens).toEqual([tok("c")]);
    expect(customerPush?.notification?.body).not.toMatch(/\d{3,}/); // no amounts
    const adminPush = m.calls.find((c) => c.data?.audience === "admin");
    expect(adminPush?.data?.type).toBe("admin_payment_issue");
    // replay
    const again = await handleStripeEventCreated("evt_1", record("refunded_reservation_lost:expired"), deps(m));
    expect(again.map((x) => x.outcome)).toEqual(["duplicate", "duplicate"]);
  });

  it("refund with an unknown session: admin alerted, customer notice skipped (no throw)", async () => {
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    const m = fakeMessaging();
    const r = await handleStripeEventCreated("evt_2", record("refunded_reservation_lost:failed"), deps(m));
    expect(r).toHaveLength(1);
    expect(r[0].outcome).toBe("sent");
    expect(await inbox(ALICE)).toHaveLength(0);
  });

  it("inconsistent_order_payment -> admin only; every other ledger outcome is ignored", async () => {
    await register(ADMIN, "superAdmin", tok("a"), "ia");
    const m = fakeMessaging();
    const r = await handleStripeEventCreated("evt_3", record("inconsistent_order_payment"), deps(m));
    expect(r.map((x) => x.outcome)).toEqual(["sent"]);
    for (const o of ["finalized", "released", "already_finalized", "session_corrupt:x", ""]) {
      expect(await handleStripeEventCreated(`evt_${o}`, record(o), deps(m))).toEqual([]);
    }
    expect(m.calls).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
describe("cleanupNotificationDataForUser (Auth deletion)", () => {
  it("deletes the user's tokens, inbox and prefs - and ONLY theirs; re-runnable", async () => {
    await register(ALICE, undefined, tok("a1"), "i1");
    await register(ALICE, undefined, tok("a2"), "i2");
    await register(BOB, undefined, tok("b1"), "i3");
    await testDb.doc(`users/${ALICE}/notifications/n1`).set({ title: "x" });
    await testDb.doc(`users/${ALICE}/notifications/n2`).set({ title: "y" });
    await testDb.doc(`users/${ALICE}/notificationSettings/prefs`).set({ pushOrders: false });
    await testDb.doc(`users/${BOB}/notifications/n1`).set({ title: "bob" });
    await testDb.doc(`users/${BOB}/notificationSettings/prefs`).set({ pushOrders: false });

    await cleanupNotificationDataForUser(ALICE);
    expect(await tokenDocs(ALICE)).toHaveLength(0);
    expect(await inbox(ALICE)).toHaveLength(0);
    expect((await testDb.doc(`users/${ALICE}/notificationSettings/prefs`).get()).exists).toBe(false);

    expect(await tokenDocs(BOB)).toHaveLength(1);
    expect(await inbox(BOB)).toHaveLength(1);
    expect((await testDb.doc(`users/${BOB}/notificationSettings/prefs`).get()).exists).toBe(true);

    await expect(cleanupNotificationDataForUser(ALICE)).resolves.toBeUndefined();
  });
});
