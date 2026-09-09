import { beforeEach, describe, expect, it } from "vitest";

import { createPaymentIntentHandler } from "../src/createPaymentIntent";
import { stripeWebhookHandler } from "../src/stripeWebhook";
import { applyCancelAdjustment, applyFavoriteChange } from "../src/lib/productStats";
import {
  clearFirestore,
  makeFakeStripe,
  makePaymentIntentEvent,
  readSession,
  seedAddress,
  seedDefaultPointer,
  seedProduct,
  signStripeEvent,
  testDb,
  TEST_WEBHOOK_SECRET,
} from "./helpers/emulator";

const UID = "alice-uid";
const ADDRESS_ID = "addr-1";
const NOW = 1_700_000_000_000;

let stripe: ReturnType<typeof makeFakeStripe>;
let evt = 0;

async function reserve(items: { productId: string; quantity: number }[]) {
  const r = await createPaymentIntentHandler({
    authUid: UID,
    data: {
      addressId: ADDRESS_ID,
      idempotencyKey: `idem-${Math.random().toString(36).slice(2)}-k`,
      items: items.map((i) => ({ ...i, selectedColor: null, selectedSize: null })),
    },
    stripe: stripe.api,
    now: () => NOW,
  });
  const session = await readSession(r.checkoutSessionId);
  return {
    sessionId: r.checkoutSessionId,
    piId: session!.stripePaymentIntentId as string,
    amountMinor: r.amount,
  };
}

async function fireSucceeded(r: { piId: string; sessionId: string; amountMinor: number }) {
  const event = makePaymentIntentEvent({
    eventId: `evt_${++evt}_${Math.random().toString(36).slice(2)}`,
    type: "payment_intent.succeeded",
    paymentIntentId: r.piId,
    amountMinor: r.amountMinor,
    checkoutSessionId: r.sessionId,
    firebaseUserId: UID,
  });
  const { rawBody, signature } = signStripeEvent(event);
  return stripeWebhookHandler({
    rawBody,
    signature,
    webhookSecret: TEST_WEBHOOK_SECRET,
    stripe: stripe.api,
    now: () => NOW,
  });
}

async function unitsSold(productId: string): Promise<number> {
  const s = await testDb.doc(`productStats/${productId}`).get();
  return (s.data()?.unitsSold as number | undefined) ?? -1;
}
async function favoriteCount(productId: string): Promise<number> {
  const s = await testDb.doc(`productStats/${productId}`).get();
  return (s.data()?.favoriteCount as number | undefined) ?? -1;
}
async function voterExists(productId: string, uid: string): Promise<boolean> {
  return (await testDb.doc(`productStats/${productId}/favoriteVoters/${uid}`).get()).exists;
}
async function addFavorite(uid: string, productId: string): Promise<void> {
  await testDb.doc(`users/${uid}/favorites/${productId}`).set({ addedAt: NOW });
}
async function removeFavorite(uid: string, productId: string): Promise<void> {
  await testDb.doc(`users/${uid}/favorites/${productId}`).delete();
}

beforeEach(async () => {
  await clearFirestore();
  await seedAddress(UID, ADDRESS_ID);
  await seedDefaultPointer(UID, ADDRESS_ID);
  stripe = makeFakeStripe();
  evt = 0;
});

describe("productStats.unitsSold via the webhook finalize path", () => {
  it("increments by the purchased quantity, aggregated by product, exactly once", async () => {
    await seedProduct("p1", { stockQuantity: 20 });
    await seedProduct("p2", { stockQuantity: 20 });
    const r = await reserve([
      { productId: "p1", quantity: 2 },
      { productId: "p1", quantity: 1 },
      { productId: "p2", quantity: 5 },
    ]);

    expect((await fireSucceeded(r)).body).toBe("finalized");
    expect(await unitsSold("p1")).toBe(3);
    expect(await unitsSold("p2")).toBe(5);

    // Re-deliver the SAME succeeded event — order already exists → no re-count.
    await fireSucceeded(r);
    expect(await unitsSold("p1")).toBe(3);
    expect(await unitsSold("p2")).toBe(5);
  });
});

describe("applyCancelAdjustment", () => {
  it("decrements exactly once and is a no-op on a duplicate delivery", async () => {
    await testDb.doc("productStats/p1").set({ unitsSold: 5 });
    await testDb.doc("productStats/p2").set({ unitsSold: 4 });
    const items = [
      { productId: "p1", quantity: 2 },
      { productId: "p2", quantity: 1 },
    ];

    const first = await applyCancelAdjustment("ord-1", items);
    expect(first.kind).toBe("applied");
    expect(await unitsSold("p1")).toBe(3);
    expect(await unitsSold("p2")).toBe(3);
    expect((await testDb.doc("statsAdjustments/ord-1").get()).exists).toBe(true);

    const second = await applyCancelAdjustment("ord-1", items);
    expect(second.kind).toBe("already_applied");
    expect(await unitsSold("p1")).toBe(3);
    expect(await unitsSold("p2")).toBe(3);
  });

  it("never drives unitsSold below zero", async () => {
    await testDb.doc("productStats/p1").set({ unitsSold: 1 });
    await applyCancelAdjustment("ord-2", [{ productId: "p1", quantity: 9 }]);
    expect(await unitsSold("p1")).toBe(0);
  });

  it("is a no-op for an order with no usable items", async () => {
    const out = await applyCancelAdjustment("ord-3", []);
    expect(out.kind).toBe("noop_no_items");
  });
});

describe("applyFavoriteChange — reconciles against the authoritative favourite doc", () => {
  it("counts each (user,product) favourite exactly once; duplicate deliveries are no-ops", async () => {
    await addFavorite("u1", "p1");
    expect((await applyFavoriteChange({ productId: "p1", uid: "u1" })).kind).toBe("incremented");
    expect(await favoriteCount("p1")).toBe(1);
    expect(await voterExists("p1", "u1")).toBe(true);

    // duplicate "create" delivery — favourite still exists, already counted
    expect((await applyFavoriteChange({ productId: "p1", uid: "u1" })).kind).toBe("already_counted");
    expect(await favoriteCount("p1")).toBe(1);

    // a different user
    await addFavorite("u2", "p1");
    await applyFavoriteChange({ productId: "p1", uid: "u2" });
    expect(await favoriteCount("p1")).toBe(2);

    // u1 unfavourites — favourite doc gone, reconcile decrements
    await removeFavorite("u1", "p1");
    expect((await applyFavoriteChange({ productId: "p1", uid: "u1" })).kind).toBe("decremented");
    expect(await favoriteCount("p1")).toBe(1);
    expect(await voterExists("p1", "u1")).toBe(false);

    // duplicate "delete" delivery
    expect((await applyFavoriteChange({ productId: "p1", uid: "u1" })).kind).toBe("already_removed");
    expect(await favoriteCount("p1")).toBe(1);
  });

  it("a delete event that lands BEFORE the create's effect still converges to the real state", async () => {
    // Rapid favourite → unfavourite: final authoritative state = NOT favourited.
    await addFavorite("u1", "p1");
    await removeFavorite("u1", "p1");

    // The "removed" event is processed first (nothing counted yet) …
    expect((await applyFavoriteChange({ productId: "p1", uid: "u1" })).kind).toBe("already_removed");
    // … then the stale "added" event arrives. It must NOT leave a phantom +1.
    expect((await applyFavoriteChange({ productId: "p1", uid: "u1" })).kind).toBe("already_removed");

    // No phantom count, and no needless productStats doc was even created
    // (favoriteCount() returns -1 for an absent doc).
    expect(await favoriteCount("p1")).toBeLessThanOrEqual(0);
    expect(await voterExists("p1", "u1")).toBe(false);
  });

  it("rapid remove/re-add ends with favoriteCount and the voter guard matching Firestore", async () => {
    await addFavorite("u1", "p1");
    await applyFavoriteChange({ productId: "p1", uid: "u1" }); // count 1

    await removeFavorite("u1", "p1");
    await addFavorite("u1", "p1"); // authoritative final state: favourited

    // Whatever order the two events fire in, every delivery reconciles to truth.
    await applyFavoriteChange({ productId: "p1", uid: "u1" });
    await applyFavoriteChange({ productId: "p1", uid: "u1" });

    expect(await favoriteCount("p1")).toBe(1);
    expect(await voterExists("p1", "u1")).toBe(true);
  });

  it("never drives favoriteCount below zero even if the aggregate is already wrong", async () => {
    await testDb.doc("productStats/p1").set({ favoriteCount: 0 });
    await testDb.doc("productStats/p1/favoriteVoters/u1").set({ at: NOW }); // stray guard, no favourite
    // No favourite doc → reconcile removes the stray guard, floors at 0.
    expect((await applyFavoriteChange({ productId: "p1", uid: "u1" })).kind).toBe("decremented");
    expect(await favoriteCount("p1")).toBe(0);
    expect(await voterExists("p1", "u1")).toBe(false);
  });

  it("keeps different users and different products isolated", async () => {
    await addFavorite("u1", "p1");
    await addFavorite("u2", "p2");
    await applyFavoriteChange({ productId: "p1", uid: "u1" });
    await applyFavoriteChange({ productId: "p2", uid: "u2" });
    expect(await favoriteCount("p1")).toBe(1);
    expect(await favoriteCount("p2")).toBe(1);

    await removeFavorite("u1", "p1");
    await applyFavoriteChange({ productId: "p1", uid: "u1" });
    expect(await favoriteCount("p1")).toBe(0);
    expect(await favoriteCount("p2")).toBe(1); // untouched
  });

  it("is compatible with a backfill-created voter guard (later trigger is a no-op)", async () => {
    // Backfill state: favourite exists, guard doc + count already written.
    await addFavorite("u1", "p1");
    await testDb.doc("productStats/p1").set({ favoriteCount: 1 });
    await testDb.doc("productStats/p1/favoriteVoters/u1").set({ at: NOW });

    // A later "create" trigger for the same favourite must not double-count.
    expect((await applyFavoriteChange({ productId: "p1", uid: "u1" })).kind).toBe("already_counted");
    expect(await favoriteCount("p1")).toBe(1);

    // And a later unfavourite still decrements exactly once.
    await removeFavorite("u1", "p1");
    await applyFavoriteChange({ productId: "p1", uid: "u1" });
    expect(await favoriteCount("p1")).toBe(0);
  });
});
