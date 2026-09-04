import { beforeEach, describe, expect, it } from "vitest";

import { createPaymentIntentHandler } from "../src/createPaymentIntent";
import { stripeWebhookHandler } from "../src/stripeWebhook";
import {
  deterministicOrderId,
  deterministicPaymentId,
} from "../src/lib/webhook";
import {
  clearFirestore,
  makeFakeStripe,
  makePaymentIntentEvent,
  readOrder,
  readPayment,
  readProductStock,
  readSession,
  readStripeEvent,
  seedAddress,
  seedDefaultPointer,
  seedProduct,
  signStripeEvent,
  testDb,
  TEST_WEBHOOK_SECRET,
  FieldValue,
  type StripeEventObject,
} from "./helpers/emulator";

const UID = "alice-uid";
const OTHER_UID = "bob-uid";
const ADDRESS_ID = "addr-1";
const NOW = 1_700_000_000_000;

let evtCounter = 0;
function eventId(): string {
  evtCounter += 1;
  return `evt_test_${evtCounter}_${Math.random().toString(36).slice(2)}`;
}

// One fake Stripe per test - shared between the reservation and the webhook
// so PaymentIntent state (status, cancel, refund) is consistent.
let stripe: ReturnType<typeof makeFakeStripe>;

/** Run a real reservation via createPaymentIntent and return its identifiers. */
async function reserve(
  opts: {
    items?: { productId: string; quantity: number; selectedColor?: string | null; selectedSize?: string | null }[];
    idempotencyKey?: string;
    uid?: string;
  } = {},
) {
  const result = await createPaymentIntentHandler({
    authUid: opts.uid ?? UID,
    data: {
      addressId: ADDRESS_ID,
      idempotencyKey: opts.idempotencyKey ?? `idem-${Math.random().toString(36).slice(2)}-key`,
      items: opts.items ?? [{ productId: "p1", quantity: 1 }],
    },
    stripe: stripe.api,
    now: () => NOW,
  });
  const session = await readSession(result.checkoutSessionId);
  return {
    sessionId: result.checkoutSessionId,
    piId: session!.stripePaymentIntentId as string,
    amountMinor: result.amount,
    totals: result.totals,
    session: session!,
  };
}

async function fire(
  event: StripeEventObject,
  opts: { tamper?: boolean; badSecret?: boolean; noSignature?: boolean; now?: number } = {},
) {
  let { rawBody, signature } = signStripeEvent(event);
  if (opts.tamper) rawBody = rawBody.replace(/}$/, ',"x":1}');
  if (opts.badSecret) {
    signature = signStripeEvent({ ...event, id: "evt_other" }).signature; // signed, but for a different payload
  }
  return stripeWebhookHandler({
    rawBody,
    signature: opts.noSignature ? undefined : signature,
    webhookSecret: TEST_WEBHOOK_SECRET,
    stripe: stripe.api,
    now: () => opts.now ?? NOW,
  });
}

function succeededEvent(r: { piId: string; sessionId: string; amountMinor: number }, over: Partial<Parameters<typeof makePaymentIntentEvent>[0]> = {}) {
  return makePaymentIntentEvent({
    eventId: eventId(),
    type: "payment_intent.succeeded",
    paymentIntentId: r.piId,
    amountMinor: r.amountMinor,
    checkoutSessionId: r.sessionId,
    firebaseUserId: UID,
    ...over,
  });
}

beforeEach(async () => {
  await clearFirestore();
  await seedAddress(UID, ADDRESS_ID);
  await seedDefaultPointer(UID, ADDRESS_ID);
  evtCounter = 0;
  stripe = makeFakeStripe();
});

describe("stripeWebhook - signature verification", () => {
  it("processes a validly-signed success event", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    const res = await fire(succeededEvent(r));
    expect(res.statusCode).toBe(200);
    expect(res.body).toBe("finalized");
  });

  it("rejects a tampered body with 400 and writes nothing", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    const res = await fire(succeededEvent(r), { tamper: true });
    expect(res.statusCode).toBe(400);
    expect(await readOrder(deterministicOrderId(r.piId))).toBeUndefined();
    expect((await readSession(r.sessionId))!.status).toBe("reserved");
  });

  it("rejects a missing signature header with 400", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    expect((await fire(succeededEvent(r), { noSignature: true })).statusCode).toBe(400);
  });

  it("rejects a signature that does not match the payload with 400", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    expect((await fire(succeededEvent(r), { badSecret: true })).statusCode).toBe(400);
  });
});

describe("stripeWebhook - sandbox-only enforcement", () => {
  it("rejects a live-mode event with 400 even when validly signed", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    const res = await fire(succeededEvent(r, { livemode: true }));
    expect(res.statusCode).toBe(400);
    expect(res.body).toContain("live-mode");
    expect(await readOrder(deterministicOrderId(r.piId))).toBeUndefined();
  });
});

describe("stripeWebhook - success finalization", () => {
  it("creates the exact Order + Payment from the session snapshot and marks the session succeeded", async () => {
    await seedProduct("p1", { stockQuantity: 8, priceAmount: 3000, title: "Oak Chair" });
    const r = await reserve({ items: [{ productId: "p1", quantity: 2 }] });
    const stockAfterReserve = await readProductStock("p1"); // 6

    const res = await fire(succeededEvent(r));
    expect(res.statusCode).toBe(200);

    const orderId = deterministicOrderId(r.piId);
    const paymentId = deterministicPaymentId(r.piId);
    const order = await readOrder(orderId);
    const payment = await readPayment(paymentId);

    expect(Object.keys(order!).sort()).toEqual(
      [
        "userId",
        "paymentId",
        "items",
        "orderDate",
        "subtotal",
        "deliveryFee",
        "discount",
        "total",
        "paymentMethod",
        "paymentStatus",
        "orderStatus",
        "deliveryAddress",
        "estimatedDeliveryStart",
        "estimatedDeliveryEnd",
      ].sort(),
    );
    expect(order!.userId).toBe(UID);
    expect(order!.paymentId).toBe(paymentId);
    expect(order!.paymentMethod).toBe("stripeCard");
    expect(order!.paymentStatus).toBe("paid");
    expect(order!.orderStatus).toBe("pending");
    expect(order!.total).toBe(r.totals.total);
    expect((order!.items as Record<string, unknown>[])[0]).toMatchObject({
      productId: "p1",
      productName: "Oak Chair",
      quantity: 2,
      unitPrice: 3000,
      lineTotal: 6000,
    });
    expect(Object.keys(order!.deliveryAddress as object).sort()).toEqual(
      ["id", "label", "fullName", "phoneNumber", "addressLine1", "addressLine2", "city", "provinceOrState", "postalCode", "isDefault"].sort(),
    );

    expect(payment).toEqual({
      userId: UID,
      orderId,
      amount: r.totals.total,
      method: "stripeCard",
      status: "paid",
      createdAt: payment!.createdAt,
    });

    const session = await readSession(r.sessionId);
    expect(session!.status).toBe("succeeded");
    expect(session!.orderId).toBe(orderId);

    // Stock is NOT touched on success - it was decremented at reservation time.
    expect(await readProductStock("p1")).toBe(stockAfterReserve);

    const ledger = await readStripeEvent((await lastEventIdFor(r.sessionId)) ?? "");
    expect(ledger?.outcome).toBe("finalized");
  });
});

// Helper: find the most recent stripeEvents doc for a session.
async function lastEventIdFor(checkoutSessionId: string): Promise<string | null> {
  const snap = await testDb
    .collection("stripeEvents")
    .where("checkoutSessionId", "==", checkoutSessionId)
    .get();
  return snap.empty ? null : snap.docs[snap.docs.length - 1].id;
}

describe("stripeWebhook - idempotency & duplicates", () => {
  it("the same event delivered twice creates the order once", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    const evt = succeededEvent(r);

    expect((await fire(evt)).body).toBe("finalized");
    expect((await fire(evt)).body).toBe("duplicate_event");

    const orders = await testDb.collection("orders").get();
    const payments = await testDb.collection("payments").get();
    expect(orders.size).toBe(1);
    expect(payments.size).toBe(1);
    const events = await testDb.collection("stripeEvents").get();
    expect(events.size).toBe(1);
  });

  it("a re-sent success with a NEW event id does not duplicate the order (deterministic ids + session state)", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();

    expect((await fire(succeededEvent(r))).body).toBe("finalized");
    expect((await fire(succeededEvent(r))).body).toBe("already_finalized");

    expect((await testDb.collection("orders").get()).size).toBe(1);
    expect((await testDb.collection("payments").get()).size).toBe(1);
  });
});

describe("stripeWebhook - mismatch rejection (verify before mutate)", () => {
  it("rejects an amount mismatch without creating anything", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    const stockAfterReserve = await readProductStock("p1");

    const res = await fire(succeededEvent(r, { amountMinor: r.amountMinor + 1 }));
    expect(res.statusCode).toBe(200);
    expect(res.body).toBe("mismatch:amount");

    expect(await readOrder(deterministicOrderId(r.piId))).toBeUndefined();
    expect(await readPayment(deterministicPaymentId(r.piId))).toBeUndefined();
    expect((await readSession(r.sessionId))!.status).toBe("reserved");
    expect(await readProductStock("p1")).toBe(stockAfterReserve);
  });

  it("rejects a currency mismatch", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    expect((await fire(succeededEvent(r, { currency: "usd" }))).body).toBe("mismatch:currency");
  });

  it("rejects a PaymentIntent-id mismatch (session bound to a different PI)", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    await testDb.doc(`checkoutSessions/${r.sessionId}`).update({ stripePaymentIntentId: "pi_something_else" });
    expect((await fire(succeededEvent(r))).body).toBe("mismatch:payment_intent_id");
  });

  it("rejects a user mismatch", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    expect((await fire(succeededEvent(r, { firebaseUserId: OTHER_UID }))).body).toBe("mismatch:user");
  });
});

describe("stripeWebhook - failure / cancellation restoration", () => {
  it("payment_failed for a reserved session restores stock once and marks it failed", async () => {
    await seedProduct("p1", { stockQuantity: 10 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 3 }] });
    expect(await readProductStock("p1")).toBe(7);

    const evt = makePaymentIntentEvent({
      eventId: eventId(),
      type: "payment_intent.payment_failed",
      paymentIntentId: r.piId,
      amountMinor: r.amountMinor,
      checkoutSessionId: r.sessionId,
      firebaseUserId: UID,
    });
    const before = (await testDb.doc(`products/p1`).get()).data()!.lastStockUpdatedAt;
    const res = await fire(evt);
    expect(res.body).toBe("released");
    // Phase 8.13.4 point 5: the PaymentIntent was CANCELLED before the restore.
    expect(stripe.calls.cancel.length).toBe(1);
    expect(stripe.getStatus(r.piId)).toBe("canceled");
    expect(await readProductStock("p1")).toBe(10);
    expect((await readSession(r.sessionId))!.status).toBe("failed");
    const after = (await testDb.doc(`products/p1`).get()).data()!.lastStockUpdatedAt;
    expect(after).not.toEqual(before); // re-stamped
  });

  it("payment_failed does NOT restore stock while the PaymentIntent could still succeed (point 5)", async () => {
    await seedProduct("p1", { stockQuantity: 8 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 2 }] });
    // The customer actually completed payment; a stray/late payment_failed arrives.
    stripe.setStatus(r.piId, "succeeded");

    const evt = makePaymentIntentEvent({
      eventId: eventId(),
      type: "payment_intent.payment_failed",
      paymentIntentId: r.piId,
      amountMinor: r.amountMinor,
      checkoutSessionId: r.sessionId,
      firebaseUserId: UID,
    });
    const res = await fire(evt);
    expect(res.body).toBe("deferred_pi_could_still_succeed");
    expect(stripe.calls.cancel.length).toBe(0); // never even attempted a cancel
    expect(await readProductStock("p1")).toBe(6); // NOT restored
    expect((await readSession(r.sessionId))!.status).toBe("reserved");
  });

  it("payment_intent.canceled behaves the same", async () => {
    await seedProduct("p1", { stockQuantity: 4 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 2 }] });
    const evt = makePaymentIntentEvent({
      eventId: eventId(),
      type: "payment_intent.canceled",
      paymentIntentId: r.piId,
      amountMinor: r.amountMinor,
      checkoutSessionId: r.sessionId,
      firebaseUserId: UID,
    });
    expect((await fire(evt)).body).toBe("released");
    expect(await readProductStock("p1")).toBe(4);
    expect((await readSession(r.sessionId))!.status).toBe("failed");
  });

  it("a repeated payment_failed (new event id) does NOT restore stock twice", async () => {
    await seedProduct("p1", { stockQuantity: 10 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 3 }] });

    const mk = () =>
      makePaymentIntentEvent({
        eventId: eventId(),
        type: "payment_intent.payment_failed",
        paymentIntentId: r.piId,
        amountMinor: r.amountMinor,
        checkoutSessionId: r.sessionId,
        firebaseUserId: UID,
      });

    expect((await fire(mk())).body).toBe("released");
    expect((await fire(mk())).body).toBe("already_released");
    expect(await readProductStock("p1")).toBe(10); // restored exactly once
  });

  it("failure for a missing session records the event and does not fault", async () => {
    const evt = makePaymentIntentEvent({
      eventId: eventId(),
      type: "payment_intent.payment_failed",
      paymentIntentId: "pi_orphan",
      amountMinor: 1000,
      checkoutSessionId: "session-that-does-not-exist",
      firebaseUserId: UID,
    });
    const res = await fire(evt);
    expect(res.statusCode).toBe(200);
    expect(res.body).toBe("session_missing");
  });
});

describe("stripeWebhook - out-of-order lifecycle", () => {
  it("payment succeeds AFTER the reservation was released: idempotent refund, no order (point 6)", async () => {
    await seedProduct("p1", { stockQuantity: 6 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 2 }] });
    // Simulate the sweep having already expired this reservation (stock back).
    await testDb.doc(`checkoutSessions/${r.sessionId}`).update({ status: "expired" });
    await testDb.doc(`products/p1`).update({ stockQuantity: 6 });

    const succeeded = succeededEvent(r);
    const res = await fire(succeeded);
    expect(res.statusCode).toBe(200);
    expect(res.body).toBe("refunded_reservation_lost:expired");
    expect(stripe.calls.refund.length).toBe(1);
    expect(stripe.calls.refund[0].options?.idempotencyKey).toContain("refund_reservation_lost_");

    // No order is created; session and stock untouched by the "success".
    expect(await readOrder(deterministicOrderId(r.piId))).toBeUndefined();
    expect(await readPayment(deterministicPaymentId(r.piId))).toBeUndefined();
    expect((await readSession(r.sessionId))!.status).toBe("expired");
    expect(await readProductStock("p1")).toBe(6);

    // A duplicate delivery of the same event does NOT refund again.
    const res2 = await fire(succeeded);
    expect(res2.body).toBe("duplicate_event");
    expect(stripe.calls.refund.length).toBe(1);
  });

  it("succeeded THEN failed for the same PI: stock is NOT restored after a successful order", async () => {
    await seedProduct("p1", { stockQuantity: 6 });
    const r = await reserve({ items: [{ productId: "p1", quantity: 2 }] });
    expect(await readProductStock("p1")).toBe(4);

    expect((await fire(succeededEvent(r))).body).toBe("finalized");

    const failedEvt = makePaymentIntentEvent({
      eventId: eventId(),
      type: "payment_intent.payment_failed",
      paymentIntentId: r.piId,
      amountMinor: r.amountMinor,
      checkoutSessionId: r.sessionId,
      firebaseUserId: UID,
    });
    const res = await fire(failedEvt);
    expect(res.body).toBe("ignored_already_succeeded");

    expect(await readProductStock("p1")).toBe(4); // still sold
    expect(await readOrder(deterministicOrderId(r.piId))).toBeDefined();
    expect((await readSession(r.sessionId))!.status).toBe("succeeded");
  });
});

describe("stripeWebhook - transaction rollback (no partial state)", () => {
  it("a fault inside the finalize transaction commits nothing and returns 500", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();

    // `now: NaN` -> Timestamp.fromMillis(NaN) throws inside the transaction,
    // after the reads, before any write.
    const res = await fire(succeededEvent(r), { now: Number.NaN });
    expect(res.statusCode).toBe(500);

    expect(await readOrder(deterministicOrderId(r.piId))).toBeUndefined();
    expect(await readPayment(deterministicPaymentId(r.piId))).toBeUndefined();
    expect((await readSession(r.sessionId))!.status).toBe("reserved");
    expect((await testDb.collection("stripeEvents").get()).empty).toBe(true);
    expect(await readProductStock("p1")).toBe(4); // unchanged since reservation
  });

  it("an inconsistent pre-existing payment (no order) is not 'repaired' by half-writing", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    const paymentId = deterministicPaymentId(r.piId);
    await testDb.doc(`payments/${paymentId}`).set({
      userId: UID,
      orderId: deterministicOrderId(r.piId),
      amount: r.totals.total,
      method: "stripeCard",
      status: "paid",
      createdAt: FieldValue.serverTimestamp(),
    });

    const res = await fire(succeededEvent(r));
    expect(res.body).toBe("inconsistent_order_payment");
    // The order was NOT created to "match" the stray payment.
    expect(await readOrder(deterministicOrderId(r.piId))).toBeUndefined();
    expect((await readSession(r.sessionId))!.status).toBe("reserved");
  });
});

describe("stripeWebhook - corrupt session & unhandled events", () => {
  it("a corrupt session snapshot records the event and creates no order", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const r = await reserve();
    await testDb.doc(`checkoutSessions/${r.sessionId}`).update({ items: "corrupt-not-a-list" });

    const res = await fire(succeededEvent(r));
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain("session_corrupt");
    expect(await readOrder(deterministicOrderId(r.piId))).toBeUndefined();
    const ev = await lastEventIdFor(r.sessionId);
    expect((await readStripeEvent(ev!))?.outcome).toContain("session_corrupt");
  });

  it("ignores an unhandled event type with 200", async () => {
    const evt: StripeEventObject = {
      id: eventId(),
      object: "event",
      type: "charge.refunded",
      livemode: false,
      data: { object: { id: "ch_1", object: "charge" } },
    };
    const res = await fire(evt);
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain("ignored");
  });

  it("ignores a success event with no checkoutSessionId metadata", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const evt = makePaymentIntentEvent({
      eventId: eventId(),
      type: "payment_intent.succeeded",
      paymentIntentId: "pi_no_meta",
      amountMinor: 1000,
      checkoutSessionId: null,
      firebaseUserId: UID,
    });
    const res = await fire(evt);
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain("no checkoutSessionId");
    expect((await testDb.collection("orders").get()).empty).toBe(true);
  });
});
