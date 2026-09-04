import { beforeEach, describe, expect, it } from "vitest";

import { createPaymentIntentHandler } from "../src/createPaymentIntent";
import { sessionIdFor } from "../src/lib/checkoutSession";
import {
  clearFirestore,
  makeFakeStripe,
  readProduct,
  readProductStock,
  readSession,
  seedAddress,
  seedDefaultPointer,
  seedProduct,
  testDb,
} from "./helpers/emulator";

const UID = "alice-uid";
const OTHER_UID = "bob-uid";
const ADDRESS_ID = "addr-1";
const NOW = 1_700_000_000_000;

function body(overrides: Record<string, unknown> = {}) {
  return {
    addressId: ADDRESS_ID,
    idempotencyKey: `idem-${Math.random().toString(36).slice(2)}-key`,
    items: [{ productId: "p1", quantity: 1, selectedColor: null, selectedSize: null }],
    ...overrides,
  };
}

async function call(
  data: Record<string, unknown>,
  opts: { uid?: string | undefined; stripe?: ReturnType<typeof makeFakeStripe>; now?: number } = {},
) {
  const stripe = opts.stripe ?? makeFakeStripe();
  const result = await createPaymentIntentHandler({
    authUid: "uid" in opts ? opts.uid : UID,
    data,
    stripe: stripe.api,
    now: () => opts.now ?? NOW,
  });
  return { result, stripe };
}

async function expectAppError(promise: Promise<unknown>, appCode: string) {
  try {
    await promise;
  } catch (err) {
    const details = (err as { details?: Record<string, unknown> }).details ?? {};
    expect(details.appCode, `expected appCode ${appCode}, got error: ${JSON.stringify(err)}`).toBe(
      appCode,
    );
    return err as { code?: string; details?: Record<string, unknown> };
  }
  throw new Error(`expected the call to reject with appCode ${appCode}, but it resolved`);
}

beforeEach(async () => {
  await clearFirestore();
  await seedAddress(UID, ADDRESS_ID);
  await seedDefaultPointer(UID, ADDRESS_ID);
});

describe("createPaymentIntent - authentication & input", () => {
  it("rejects an unauthenticated caller", async () => {
    await seedProduct("p1");
    await expectAppError(call(body(), { uid: undefined }), "UNAUTHENTICATED");
  });

  it("rejects a malformed request body", async () => {
    await expectAppError(call({ nonsense: true }), "INVALID_REQUEST");
    await expectAppError(call(body({ items: [] })), "INVALID_REQUEST");
    await expectAppError(call(body({ idempotencyKey: "short" })), "INVALID_REQUEST");
    await expectAppError(
      call(body({ items: [{ productId: "p1", quantity: 0 }] })),
      "INVALID_REQUEST",
    );
  });
});

describe("createPaymentIntent - address ownership", () => {
  it("rejects an addressId that is not under the caller's own uid", async () => {
    await seedProduct("p1");
    // Address exists, but for a different user.
    await seedAddress(OTHER_UID, "addr-bob");
    await expectAppError(call(body({ addressId: "addr-bob" })), "ADDRESS_NOT_FOUND");
    // ...and the reservation never happened.
    expect(await readProductStock("p1")).toBe(5);
  });

  it("rejects a completely missing address", async () => {
    await seedProduct("p1");
    await expectAppError(call(body({ addressId: "does-not-exist" })), "ADDRESS_NOT_FOUND");
  });

  it("rejects an address that is missing a rules-required field", async () => {
    await seedProduct("p1");
    await seedAddress(UID, "addr-bad", { city: "" });
    await expectAppError(call(body({ addressId: "addr-bad" })), "ADDRESS_INCOMPLETE");
    expect(await readProductStock("p1")).toBe(5);
  });
});

describe("createPaymentIntent - product availability", () => {
  it("rejects a missing product", async () => {
    await expectAppError(call(body()), "PRODUCT_UNAVAILABLE");
  });

  it("rejects a draft product", async () => {
    await seedProduct("p1", { publicationStatus: "draft" });
    await expectAppError(call(body()), "PRODUCT_UNAVAILABLE");
  });

  it("rejects an inactive product", async () => {
    await seedProduct("p1", { isActive: false });
    await expectAppError(call(body()), "PRODUCT_UNAVAILABLE");
  });

  it("rejects a variant the product does not offer", async () => {
    await seedProduct("p1", { availableColors: ["black", "walnut"] });
    await expectAppError(
      call(body({ items: [{ productId: "p1", quantity: 1, selectedColor: "pink" }] })),
      "VARIANT_UNAVAILABLE",
    );
  });
});

describe("createPaymentIntent - stock", () => {
  it("rejects an out-of-stock product", async () => {
    await seedProduct("p1", { stockQuantity: 0 });
    await expectAppError(call(body()), "OUT_OF_STOCK");
  });

  it("rejects insufficient stock and reports available vs requested", async () => {
    await seedProduct("p1", { stockQuantity: 3 });
    const err = await expectAppError(
      call(body({ items: [{ productId: "p1", quantity: 5 }] })),
      "INSUFFICIENT_STOCK",
    );
    expect(err.details?.available).toBe(3);
    expect(err.details?.requested).toBe(5);
    expect(await readProductStock("p1")).toBe(3); // untouched
  });

  it("allows an EXACT-stock purchase, decrements to 0 and stamps lastStockUpdatedAt", async () => {
    await seedProduct("p1", { stockQuantity: 3 });
    const { result } = await call(body({ items: [{ productId: "p1", quantity: 3 }] }));
    expect(result.status).toBe("reserved");
    expect(await readProductStock("p1")).toBe(0);
    const product = await readProduct("p1");
    expect(product?.lastStockUpdatedAt).toBeTruthy();
    const session = await readSession(result.checkoutSessionId);
    expect(session?.status).toBe("reserved");
    expect(session?.userId).toBe(UID);
  });
});

describe("createPaymentIntent - server pricing (client cannot influence)", () => {
  it("prices from products/{id}.priceAmount only, ignoring any client-sent price fields", async () => {
    await seedProduct("p1", { priceAmount: 4000, originalPriceAmount: 9999, stockQuantity: 10 });
    const { result } = await call(
      body({
        subtotal: 1,
        total: 1,
        items: [{ productId: "p1", quantity: 2, unitPriceRupees: 1, priceAmount: 1 }],
      }),
    );
    // subtotal 8000 + delivery 500 - discount 1000 = 7500
    expect(result.totals).toEqual({
      subtotal: 8000,
      deliveryFee: 500,
      discount: 1000,
      total: 7500,
    });
    // amount is minor units (paisa): 7500 * 100
    expect(result.amount).toBe(750_000);
    expect(result.currency).toBe("pkr");
  });

  it("clamps the discount for a genuinely small cart so the session total is invariant-safe", async () => {
    await seedProduct("p1", { priceAmount: 200, stockQuantity: 10 });
    // subtotal 200 + 500 = 700; discount clamps to 700; total 0 -> rejected (Stripe needs > 0)
    await expectAppError(
      call(body({ items: [{ productId: "p1", quantity: 1 }] })),
      "ORDER_TOTAL_INVALID",
    );
  });
});

describe("createPaymentIntent - variant aggregation", () => {
  it("combines two variant lines of the same product for the stock check", async () => {
    await seedProduct("p1", { stockQuantity: 4, availableSizes: ["s", "m"] });
    await expectAppError(
      call(
        body({
          items: [
            { productId: "p1", quantity: 3, selectedSize: "s" },
            { productId: "p1", quantity: 3, selectedSize: "m" },
          ],
        }),
      ),
      "INSUFFICIENT_STOCK",
    );
    expect(await readProductStock("p1")).toBe(4);
  });

  it("decrements ONCE by the summed quantity when the combined request fits", async () => {
    await seedProduct("p1", { stockQuantity: 10, priceAmount: 1000, availableSizes: ["s", "m"] });
    const { result } = await call(
      body({
        items: [
          { productId: "p1", quantity: 2, selectedSize: "s" },
          { productId: "p1", quantity: 3, selectedSize: "m" },
        ],
      }),
    );
    expect(await readProductStock("p1")).toBe(5); // 10 - (2 + 3)
    const session = await readSession(result.checkoutSessionId);
    expect((session?.items as unknown[]).length).toBe(2); // both lines kept for the order snapshot
  });
});

describe("createPaymentIntent - concurrency (single-winner)", () => {
  it("two concurrent checkouts for the last unit: exactly one reserves, stock never goes negative", async () => {
    await seedProduct("p1", { stockQuantity: 1 });

    const results = await Promise.allSettled([
      call(body({ idempotencyKey: "concurrent-key-A-xxxx" })),
      call(body({ idempotencyKey: "concurrent-key-B-xxxx" })),
    ]);

    const fulfilled = results.filter((r) => r.status === "fulfilled");
    const rejected = results.filter((r) => r.status === "rejected");
    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    const rejectedCode =
      ((rejected[0] as PromiseRejectedResult).reason as { details?: Record<string, unknown> })
        .details?.appCode;
    expect(["OUT_OF_STOCK", "INSUFFICIENT_STOCK", "RESERVATION_CONFLICT"]).toContain(rejectedCode);
    expect(await readProductStock("p1")).toBe(0); // never -1
  });
});

describe("createPaymentIntent - idempotent retries", () => {
  it("same idempotency key + PaymentIntent already created -> returns the same secret, no new reservation", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const stripe = makeFakeStripe();
    const key = "retry-key-stable-1";

    const first = await call(body({ idempotencyKey: key }), { stripe });
    expect(await readProductStock("p1")).toBe(4);

    const second = await call(body({ idempotencyKey: key }), { stripe });
    expect(second.result.checkoutSessionId).toBe(first.result.checkoutSessionId);
    expect(second.result.paymentIntentClientSecret).toBeTruthy();
    expect(await readProductStock("p1")).toBe(4); // still decremented exactly once
    expect(stripe.calls.create).toHaveLength(1); // no second create
    expect(stripe.calls.retrieve).toHaveLength(1); // fresh secret via retrieve
  });

  it("same idempotency key after the FIRST attempt died before Stripe -> reuses the reservation, no double decrement", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const key = "retry-key-stable-2";

    // Attempt 1: reservation commits, then Stripe throws -> handler compensates.
    const failing = makeFakeStripe({ failEveryCreate: { type: "StripeConnectionError" } });
    await expectAppError(call(body({ idempotencyKey: key }), { stripe: failing }), "PAYMENT_PROVIDER_ERROR");
    // Compensation restored the stock and closed the session.
    expect(await readProductStock("p1")).toBe(5);
    const sid = sessionIdFor(UID, key);
    expect((await readSession(sid))?.status).toBe("failed");

    // Attempt 2 with the SAME key: session is `failed` -> attempt closed, client must use a new key.
    await expectAppError(call(body({ idempotencyKey: key })), "CHECKOUT_ATTEMPT_CLOSED");
    expect(await readProductStock("p1")).toBe(5);
  });

  it("retry when the reservation is intact but the PI id was never persisted -> creates via same Stripe idempotency key, no double decrement", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const key = "retry-key-stable-3";
    const sid = sessionIdFor(UID, key);

    // Attempt 1 succeeds fully.
    const stripe = makeFakeStripe();
    await call(body({ idempotencyKey: key }), { stripe });
    expect(await readProductStock("p1")).toBe(4);

    // Simulate "PI id never persisted" by clearing it on the session doc.
    await testDb.doc(`checkoutSessions/${sid}`).update({ stripePaymentIntentId: null });

    // Retry: classified `needs_payment_intent` -> create is called again, but with
    // the same Stripe idempotency key, so the fake returns the SAME PaymentIntent.
    const second = await call(body({ idempotencyKey: key }), { stripe });
    expect(second.result.paymentIntentClientSecret).toBeTruthy();
    expect(await readProductStock("p1")).toBe(4); // NOT decremented again
    expect(stripe.calls.create).toHaveLength(2);
    const createdIds = (stripe.calls.create as { options?: { idempotencyKey?: string } }[]).map(
      (c) => c.options?.idempotencyKey,
    );
    expect(createdIds[0]).toBe(createdIds[1]); // same Stripe idempotency key
  });
});

describe("createPaymentIntent - Stripe failure compensation (zero partial state)", () => {
  it("Stripe create fails -> stock fully restored, session `failed`, no PI id, clean error", async () => {
    await seedProduct("p1", { stockQuantity: 7 });
    const stripe = makeFakeStripe({ failEveryCreate: { type: "StripeAPIError", statusCode: 503 } });
    const key = "compensation-key-1-xx";

    await expectAppError(
      call(body({ idempotencyKey: key, items: [{ productId: "p1", quantity: 3 }] }), { stripe }),
      "PAYMENT_PROVIDER_ERROR",
    );

    expect(await readProductStock("p1")).toBe(7); // fully restored
    const session = await readSession(sessionIdFor(UID, key));
    expect(session?.status).toBe("failed");
    expect(session?.stripePaymentIntentId).toBeNull();
  });

  it("Stripe rejects amount_too_small -> compensated + PAYMENT_AMOUNT_TOO_SMALL", async () => {
    await seedProduct("p1", { stockQuantity: 5, priceAmount: 1000 });
    const stripe = makeFakeStripe({
      failEveryCreate: { type: "StripeInvalidRequestError", code: "amount_too_small" },
    });
    const key = "compensation-key-2-xx";
    await expectAppError(call(body({ idempotencyKey: key }), { stripe }), "PAYMENT_AMOUNT_TOO_SMALL");
    expect(await readProductStock("p1")).toBe(5);
    expect((await readSession(sessionIdFor(UID, key)))?.status).toBe("failed");
  });
});

describe("createPaymentIntent - session lifecycle on retry", () => {
  it("a completed session -> CHECKOUT_ALREADY_COMPLETED", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const key = "lifecycle-key-1-xxxx";
    await call(body({ idempotencyKey: key }));
    await testDb.doc(`checkoutSessions/${sessionIdFor(UID, key)}`).update({ status: "succeeded" });
    await expectAppError(call(body({ idempotencyKey: key })), "CHECKOUT_ALREADY_COMPLETED");
  });

  it("an expired reservation on retry -> stock restored, session `expired`, CHECKOUT_EXPIRED", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const key = "lifecycle-key-2-xxxx";
    await call(body({ idempotencyKey: key }), { now: NOW });
    expect(await readProductStock("p1")).toBe(4);

    // Retry well past the 15-minute TTL.
    await expectAppError(
      call(body({ idempotencyKey: key }), { now: NOW + 16 * 60 * 1000 }),
      "CHECKOUT_EXPIRED",
    );
    expect(await readProductStock("p1")).toBe(5); // restored by compensation
    expect((await readSession(sessionIdFor(UID, key)))?.status).toBe("expired");
  });

  it("a session owned by another user (hash collision defence) -> FORBIDDEN", async () => {
    await seedProduct("p1", { stockQuantity: 5 });
    const key = "lifecycle-key-3-xxxx";
    const sid = sessionIdFor(UID, key);
    // Force a session doc at this id but owned by someone else.
    await testDb.doc(`checkoutSessions/${sid}`).set({
      userId: OTHER_UID,
      status: "reserved",
      items: [],
      subtotal: 0,
      deliveryFee: 0,
      discount: 0,
      total: 0,
      amountMinor: 0,
      currency: "pkr",
      stripePaymentIntentId: null,
      orderId: null,
    });
    await expectAppError(call(body({ idempotencyKey: key })), "FORBIDDEN");
  });
});

describe("createPaymentIntent - session document shape", () => {
  it("stores an order-compatible address snapshot and resolved line items", async () => {
    await seedProduct("p1", { priceAmount: 2500, stockQuantity: 9, title: "Oak Chair" });
    const { result } = await call(body({ items: [{ productId: "p1", quantity: 2 }] }));
    const session = await readSession(result.checkoutSessionId);

    expect(Object.keys(session?.deliveryAddressSnapshot as object).sort()).toEqual(
      [
        "id",
        "label",
        "fullName",
        "phoneNumber",
        "addressLine1",
        "addressLine2",
        "city",
        "provinceOrState",
        "postalCode",
        "isDefault",
      ].sort(),
    );
    expect((session?.deliveryAddressSnapshot as { isDefault: boolean }).isDefault).toBe(true);

    const line = (session?.items as Record<string, unknown>[])[0];
    expect(line.unitPriceRupees).toBe(2500);
    expect(line.lineTotalRupees).toBe(5000);
    expect(line.productName).toBe("Oak Chair");
    expect(line.imagePath).toBe("products/test/main.jpg");

    expect(session?.stripePaymentIntentId).toMatch(/^pi_/);
    expect(session?.currency).toBe("pkr");
    expect(session?.amountMinor).toBe(result.amount);
  });
});
