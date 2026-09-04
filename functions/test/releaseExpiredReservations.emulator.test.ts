import { beforeEach, describe, expect, it } from "vitest";

import { sweepExpiredReservations } from "../src/lib/sweep";
import { deterministicOrderId, deterministicPaymentId } from "../src/lib/webhook";
import {
  clearFirestore,
  makeFakeStripe,
  readOrder,
  readPayment,
  readProductStock,
  readSession,
  readStripeEvent,
  reserveViaHandler,
  seedAddress,
  seedDefaultPointer,
  seedProduct,
  testDb,
} from "./helpers/emulator";

const UID = "alice-uid";
const ADDRESS_ID = "addr-1";
const RESERVED_AT = 1_700_000_000_000;
const TTL_MS = 15 * 60 * 1000;
const AFTER_EXPIRY = RESERVED_AT + TTL_MS + 60_000;

let stripe: ReturnType<typeof makeFakeStripe>;

async function reserve(
  opts: { items?: { productId: string; quantity: number }[]; idempotencyKey?: string } = {},
) {
  return reserveViaHandler(stripe, {
    uid: UID,
    addressId: ADDRESS_ID,
    items: opts.items,
    idempotencyKey: opts.idempotencyKey,
    nowMs: RESERVED_AT,
  });
}

function sweep(nowMs = AFTER_EXPIRY, batchSize = 20, s = stripe) {
  return sweepExpiredReservations({ stripe: s.api, nowMs, batchSize });
}

beforeEach(async () => {
  await clearFirestore();
  await seedAddress(UID, ADDRESS_ID);
  await seedDefaultPointer(UID, ADDRESS_ID);
  stripe = makeFakeStripe(); // default: created PIs are `requires_payment_method`
});

describe("releaseExpiredReservations - expiry & cancellation", () => {
  it("cancels an unpaid PaymentIntent, restores stock exactly once, marks the session expired", async () => {
    await seedProduct("p1", { stockQuantity: 10 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 3 }] });
    expect(await readProductStock("p1")).toBe(7); // decremented at reservation

    const summary = await sweep();
    expect(summary.scanned).toBe(1);
    expect(summary.outcomes.released).toBe(1);
    expect(stripe.calls.cancel.length).toBe(1);
    expect(stripe.getStatus(r.piId)).toBe("canceled");
    expect(await readProductStock("p1")).toBe(10); // restored
    expect((await readSession(r.sessionId))!.status).toBe("expired");
    expect((await readStripeEvent(`sweep_release_${r.sessionId}`))?.outcome).toBe("released_expired");
  });

  it("does not touch a reservation that has not expired yet", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    const summary = await sweep(RESERVED_AT + 60_000); // 1 min in, well before TTL
    expect(summary.scanned).toBe(0);
    expect((await readSession(r.sessionId))!.status).toBe("reserved");
    expect(await readProductStock("p1")).toBe(4);
  });

  it("releases without a cancel call when the PaymentIntent is already canceled", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 2 }] });
    stripe.setStatus(r.piId, "canceled");

    const summary = await sweep();
    expect(summary.outcomes.released).toBe(1);
    expect(stripe.calls.cancel.length).toBe(0);
    expect(await readProductStock("p1")).toBe(5);
    expect((await readSession(r.sessionId))!.status).toBe("expired");
  });
});

describe("releaseExpiredReservations - PaymentIntent still live", () => {
  it("finalizes the order when the PaymentIntent already succeeded (never restores)", async () => {
    await seedProduct("p1", { stockQuantity: 8, priceAmount: 3000 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 2 }] });
    stripe.setStatus(r.piId, "succeeded");
    const stockAfterReserve = await readProductStock("p1"); // 6

    const summary = await sweep();
    expect(summary.outcomes.finalized).toBe(1);
    expect(stripe.calls.cancel.length).toBe(0);
    expect(await readProductStock("p1")).toBe(stockAfterReserve); // NOT restored
    expect((await readSession(r.sessionId))!.status).toBe("succeeded");
    const order = await readOrder(deterministicOrderId(r.piId));
    expect(order?.total).toBe(r.totals.total);
    expect(await readPayment(deterministicPaymentId(r.piId))).toBeDefined();
  });

  it("defers a PaymentIntent that is still processing", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 2 }] });
    stripe.setStatus(r.piId, "processing");

    const summary = await sweep();
    expect(summary.outcomes.deferred_in_progress).toBe(1);
    expect(stripe.calls.cancel.length).toBe(0);
    expect(await readProductStock("p1")).toBe(3); // unchanged
    expect((await readSession(r.sessionId))!.status).toBe("reserved");
  });

  it("defers (never restores) when a cancel attempt does not confirm cancellation", async () => {
    // `cancel` throws; the PI stays cancellable on re-check -> not safe to restore.
    const failing = makeFakeStripe({ failCancelWith: { type: "StripeAPIError" } });
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserveViaHandler(failing, {
      uid: UID,
      addressId: ADDRESS_ID,
      items: [{ productId: "p1", quantity: 2 }],
      nowMs: RESERVED_AT,
    });

    const summary = await sweep(AFTER_EXPIRY, 20, failing);
    expect(summary.outcomes.deferred_cancel_incomplete).toBe(1);
    expect(await readProductStock("p1")).toBe(3); // NOT restored
    expect((await readSession(r.sessionId))!.status).toBe("reserved");
  });
});

describe("releaseExpiredReservations - missing PaymentIntent id", () => {
  it("reconciles via the deterministic idempotency key and then releases", async () => {
    await seedProduct("p1", { stockQuantity: 6 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 2 }] });
    // Simulate the Phase 8.13.2 best-effort persist having failed.
    await testDb.doc(`checkoutSessions/${r.sessionId}`).update({ stripePaymentIntentId: null });

    const createsBefore = stripe.calls.create.length;
    const summary = await sweep();
    expect(summary.outcomes.released).toBe(1);
    // Re-issued the create with the SAME idempotency key -> same PI back.
    expect(stripe.calls.create.length).toBe(createsBefore + 1);
    const lastCreate = stripe.calls.create[stripe.calls.create.length - 1];
    expect(lastCreate.options?.idempotencyKey).toContain("pi_create_");
    expect(await readProductStock("p1")).toBe(6);
    expect((await readSession(r.sessionId))!.status).toBe("expired");
    // The PI id was back-filled onto the session.
    expect((await readSession(r.sessionId))!.stripePaymentIntentId).toBe(r.piId);
  });

  it("leaves the session reserved when a PaymentIntent cannot be resolved at all", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    // Point the session at a PI the fake does not know, and drop the data
    // needed to reconcile.
    await testDb.doc(`checkoutSessions/${r.sessionId}`).update({
      stripePaymentIntentId: "pi_unknown_to_fake",
    });

    const summary = await sweep();
    expect(summary.outcomes.no_payment_intent).toBe(1);
    expect((await readSession(r.sessionId))!.status).toBe("reserved");
    expect(await readProductStock("p1")).toBe(4); // untouched
  });
});

describe("releaseExpiredReservations - idempotency & concurrency", () => {
  it("overlapping sweeps restore stock exactly once", async () => {
    await seedProduct("p1", { stockQuantity: 10 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 4 }] });

    const [a, b] = await Promise.all([sweep(), sweep()]);
    const totalReleased = (a.outcomes.released ?? 0) + (b.outcomes.released ?? 0);
    const totalSkipped = (a.outcomes.skipped_not_expired_reserved ?? 0) + (b.outcomes.skipped_not_expired_reserved ?? 0);

    expect(totalReleased).toBe(1); // exactly one sweep did the restore
    expect(totalSkipped).toBe(1); // the other saw it was already handled
    expect(await readProductStock("p1")).toBe(10); // NOT 14
    expect((await readSession(r.sessionId))!.status).toBe("expired");
  });

  it("a second sweep run finds nothing to do", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    await reserve({ items: [{ productId: "p1", quantity: 2 }] });

    await sweep();
    const second = await sweep();
    expect(second.scanned).toBe(0);
    expect(await readProductStock("p1")).toBe(5);
  });

  it("a webhook success winning the race is not overwritten by the sweep's restore", async () => {
    await seedProduct("p1", { stockQuantity: 6 });

    // The fake flips the session to `succeeded` (as the webhook would) the
    // moment the sweep asks Stripe to cancel - i.e. AFTER the sweep already
    // classified the PI as cancellable, BEFORE its release transaction.
    let sessionId = "";
    const racing = makeFakeStripe({
      onBeforeCancel: async () => {
        await testDb.doc(`checkoutSessions/${sessionId}`).update({ status: "succeeded" });
      },
    });
    const r = await reserveViaHandler(racing, {
      uid: UID,
      addressId: ADDRESS_ID,
      items: [{ productId: "p1", quantity: 2 }],
      nowMs: RESERVED_AT,
    });
    sessionId = r.sessionId;

    const summary = await sweep(AFTER_EXPIRY, 20, racing);
    // The release transaction re-checked status and skipped.
    expect(summary.outcomes.skipped_not_expired_reserved).toBe(1);
    expect(await readProductStock("p1")).toBe(4); // NOT restored to 6
    expect((await readSession(r.sessionId))!.status).toBe("succeeded");
  });
});

describe("releaseExpiredReservations - bounded & fault-isolated", () => {
  it("respects the batch size and reports hadMore", async () => {
    await seedProduct("p1", { stockQuantity: 999 });
    for (let i = 0; i < 25; i++) {
      await reserve({ items: [{ productId: "p1", quantity: 1 }], idempotencyKey: `batch-key-${i}-xxxx` });
    }
    const summary = await sweep(AFTER_EXPIRY, 20);
    expect(summary.scanned).toBe(20);
    expect(summary.hadMore).toBe(true);
  });

  it("one unresolvable session does not stop the rest of the sweep", async () => {
    await seedProduct("p1", { stockQuantity: 20 });
    const good1 = await reserve({ items: [{ productId: "p1", quantity: 2 }], idempotencyKey: "good-one-key-xxxx" });
    const good2 = await reserve({ items: [{ productId: "p1", quantity: 3 }], idempotencyKey: "good-two-key-xxxx" });
    const bad = await reserve({ items: [{ productId: "p1", quantity: 1 }], idempotencyKey: "bad-one-key-xxxxx" });
    await testDb.doc(`checkoutSessions/${bad.sessionId}`).update({ stripePaymentIntentId: "pi_unknown" });

    const summary = await sweep();
    expect(summary.scanned).toBe(3);
    expect(summary.errors).toBe(0); // isolated, not thrown
    expect((summary.outcomes.released ?? 0)).toBe(2);
    expect(summary.outcomes.no_payment_intent).toBe(1);
    expect((await readSession(good1.sessionId))!.status).toBe("expired");
    expect((await readSession(good2.sessionId))!.status).toBe("expired");
    expect((await readSession(bad.sessionId))!.status).toBe("reserved");
    expect(await readProductStock("p1")).toBe(19); // 20 - 1 (only the bad reservation still holds)
  });
});
