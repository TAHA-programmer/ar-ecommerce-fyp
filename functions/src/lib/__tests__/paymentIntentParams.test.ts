import { describe, it, expect } from "vitest";

import { buildPaymentIntentCreateParams } from "../paymentIntentParams";

describe("buildPaymentIntentCreateParams", () => {
  it("is deterministic for the same session/amount/user", () => {
    const a = buildPaymentIntentCreateParams({ sessionId: "s".repeat(64), amountMinor: 750000, firebaseUserId: "u1" });
    const b = buildPaymentIntentCreateParams({ sessionId: "s".repeat(64), amountMinor: 750000, firebaseUserId: "u1" });
    expect(a).toEqual(b);
  });

  it("carries PKR, card-only, and the exact metadata the webhook/sweep read back", () => {
    const p = buildPaymentIntentCreateParams({
      sessionId: "abcdef0123456789",
      amountMinor: 450000,
      firebaseUserId: "alice",
    });
    expect(p).toEqual({
      amount: 450000,
      currency: "pkr",
      payment_method_types: ["card"],
      description: "TWin AR order (session abcdef012345)",
      metadata: {
        checkoutSessionId: "abcdef0123456789",
        firebaseUserId: "alice",
        appPhase: "twin_ar_8_13_2",
      },
    });
  });

  it("changes only where an input changes (so a reused Stripe idempotency key stays valid)", () => {
    const base = buildPaymentIntentCreateParams({ sessionId: "s1xxxxxxxxxxxx", amountMinor: 1, firebaseUserId: "u" });
    expect(buildPaymentIntentCreateParams({ sessionId: "s1xxxxxxxxxxxx", amountMinor: 2, firebaseUserId: "u" })).not.toEqual(base);
    expect(buildPaymentIntentCreateParams({ sessionId: "s1xxxxxxxxxxxx", amountMinor: 1, firebaseUserId: "v" })).not.toEqual(base);
  });
});
