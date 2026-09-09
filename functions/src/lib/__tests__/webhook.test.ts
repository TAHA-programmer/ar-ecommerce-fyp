import { describe, it, expect } from "vitest";

import {
  HANDLED_EVENT_TYPES,
  isHandledEventType,
  deterministicOrderId,
  deterministicPaymentId,
  paymentIntentFromEvent,
  verifySessionMatchesPaymentIntent,
  buildStripeEventRecord,
} from "../webhook";

describe("handled event types", () => {
  it("actions exactly succeeded / payment_failed / canceled", () => {
    expect([...HANDLED_EVENT_TYPES].sort()).toEqual(
      ["payment_intent.succeeded", "payment_intent.payment_failed", "payment_intent.canceled"].sort(),
    );
    expect(isHandledEventType("payment_intent.succeeded")).toBe(true);
    expect(isHandledEventType("payment_intent.created")).toBe(false);
    expect(isHandledEventType("charge.refunded")).toBe(false);
  });
});

describe("deterministic ids", () => {
  it("are stable per PaymentIntent id and distinct order vs payment", () => {
    expect(deterministicOrderId("pi_abc")).toBe(deterministicOrderId("pi_abc"));
    expect(deterministicPaymentId("pi_abc")).toBe(deterministicPaymentId("pi_abc"));
    expect(deterministicOrderId("pi_abc")).not.toBe(deterministicPaymentId("pi_abc"));
    expect(deterministicOrderId("pi_abc")).not.toBe(deterministicOrderId("pi_xyz"));
  });
  it("are valid Firestore id shapes", () => {
    expect(deterministicOrderId("pi_abc")).toMatch(/^ord_[0-9a-f]{40}$/);
    expect(deterministicPaymentId("pi_abc")).toMatch(/^pay_[0-9a-f]{40}$/);
  });
});

describe("paymentIntentFromEvent", () => {
  it("extracts only id / amount / currency / string metadata (never client_secret)", () => {
    const pi = paymentIntentFromEvent({
      data: {
        object: {
          id: "pi_1",
          amount: 750000,
          currency: "pkr",
          client_secret: "pi_1_secret_LEAK",
          latest_charge: { id: "ch_1", payment_method_details: { card: { last4: "4242" } } },
          metadata: { checkoutSessionId: "s1", firebaseUserId: "u1", bogus: 5 },
        },
      },
    });
    expect(pi).toEqual({
      id: "pi_1",
      amount: 750000,
      currency: "pkr",
      metadata: { checkoutSessionId: "s1", firebaseUserId: "u1" },
    });
    expect(JSON.stringify(pi)).not.toContain("secret");
    expect(JSON.stringify(pi)).not.toContain("4242");
  });

  it("returns null for a missing / malformed PaymentIntent", () => {
    expect(paymentIntentFromEvent({})).toBeNull();
    expect(paymentIntentFromEvent({ data: {} })).toBeNull();
    expect(paymentIntentFromEvent({ data: { object: { amount: 1 } } })).toBeNull();
  });
});

describe("verifySessionMatchesPaymentIntent", () => {
  const session = {
    userId: "u1",
    currency: "pkr",
    amountMinor: 750000,
    stripePaymentIntentId: "pi_1",
  };
  const pi = {
    id: "pi_1",
    amount: 750000,
    currency: "PKR",
    metadata: { checkoutSessionId: "s1", firebaseUserId: "u1" },
  };

  it("passes when everything matches (currency case-insensitive)", () => {
    expect(verifySessionMatchesPaymentIntent(session, pi, "s1")).toBeNull();
  });

  it("catches each individual mismatch", () => {
    expect(verifySessionMatchesPaymentIntent(session, pi, "s-other")).toBe("metadata_session_id");
    expect(
      verifySessionMatchesPaymentIntent({ ...session, stripePaymentIntentId: "pi_2" }, pi, "s1"),
    ).toBe("payment_intent_id");
    expect(
      verifySessionMatchesPaymentIntent(session, { ...pi, metadata: { checkoutSessionId: "s1", firebaseUserId: "someone-else" } }, "s1"),
    ).toBe("user");
    expect(verifySessionMatchesPaymentIntent(session, { ...pi, currency: "usd" }, "s1")).toBe("currency");
    expect(verifySessionMatchesPaymentIntent(session, { ...pi, amount: 1 }, "s1")).toBe("amount");
    expect(verifySessionMatchesPaymentIntent(session, { ...pi, amount: Number.NaN }, "s1")).toBe("amount");
  });

  it("tolerates a null stored PaymentIntent id (8.13.2 best-effort persist can fail)", () => {
    expect(
      verifySessionMatchesPaymentIntent({ ...session, stripePaymentIntentId: null }, pi, "s1"),
    ).toBeNull();
  });
});

describe("buildStripeEventRecord", () => {
  it("stores only safe identifiers", () => {
    const rec = buildStripeEventRecord({
      eventId: "evt_1",
      type: "payment_intent.succeeded",
      livemode: false,
      paymentIntentId: "pi_1",
      checkoutSessionId: "s1",
      outcome: "finalized",
      serverTimestamp: { __ts: true },
    });
    expect(rec).toEqual({
      eventId: "evt_1",
      type: "payment_intent.succeeded",
      livemode: false,
      paymentIntentId: "pi_1",
      checkoutSessionId: "s1",
      outcome: "finalized",
      processedAt: { __ts: true },
    });
    expect(JSON.stringify(rec)).not.toMatch(/secret|sk_|whsec_|card/i);
  });
});
