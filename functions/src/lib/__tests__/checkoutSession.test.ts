import { describe, it, expect } from "vitest";

import {
  CHECKOUT_SESSIONS_COLLECTION,
  RESERVATION_TTL_MS,
  isTerminalCheckoutSessionStatus,
  reservationHoldsStock,
  sessionIdFor,
  stripeIdempotencyKeyFor,
  timestampToMillis,
  classifyExistingSession,
  buildReservedSessionDoc,
  type CheckoutSessionStatus,
} from "../checkoutSession";

describe("checkoutSession constants + status model", () => {
  it("collection name matches the firestore.rules match block", () => {
    expect(CHECKOUT_SESSIONS_COLLECTION).toBe("checkoutSessions");
  });

  it("reservation TTL is 15 minutes", () => {
    expect(RESERVATION_TTL_MS).toBe(15 * 60 * 1000);
  });

  it("classifies terminal vs live statuses", () => {
    expect(isTerminalCheckoutSessionStatus("reserved")).toBe(false);
    for (const s of ["succeeded", "failed", "expired"] as const) {
      expect(isTerminalCheckoutSessionStatus(s)).toBe(true);
    }
  });

  it("only a reserved session holds stock a failure must restore", () => {
    const statuses: CheckoutSessionStatus[] = ["reserved", "succeeded", "failed", "expired"];
    expect(statuses.filter(reservationHoldsStock)).toEqual(["reserved"]);
  });
});

describe("sessionIdFor", () => {
  it("is deterministic for the same (uid, key)", () => {
    expect(sessionIdFor("uid-1", "key-abc")).toBe(sessionIdFor("uid-1", "key-abc"));
  });

  it("differs by uid and by key, and is a 64-char hex string", () => {
    const a = sessionIdFor("uid-1", "key-abc");
    const b = sessionIdFor("uid-2", "key-abc");
    const c = sessionIdFor("uid-1", "key-xyz");
    expect(a).not.toBe(b);
    expect(a).not.toBe(c);
    expect(a).toMatch(/^[0-9a-f]{64}$/);
  });

  it("cannot be collided by moving the separator (uid|key boundary is unambiguous)", () => {
    expect(sessionIdFor("a", "b c")).not.toBe(sessionIdFor("a b", "c"));
  });
});

describe("stripeIdempotencyKeyFor", () => {
  it("is deterministic and namespaced", () => {
    expect(stripeIdempotencyKeyFor("abc")).toBe("pi_create_abc");
  });
});

describe("timestampToMillis", () => {
  it("reads a Firestore-Timestamp-like object", () => {
    expect(timestampToMillis({ toMillis: () => 1234 })).toBe(1234);
    expect(timestampToMillis({ _seconds: 2, _nanoseconds: 500_000_000 })).toBe(2500);
  });
  it("passes through a finite number and rejects everything else", () => {
    expect(timestampToMillis(99)).toBe(99);
    expect(timestampToMillis(null)).toBeNull();
    expect(timestampToMillis("nope")).toBeNull();
    expect(timestampToMillis({})).toBeNull();
  });
});

describe("classifyExistingSession", () => {
  const NOW = 1_000_000;
  const future = { toMillis: () => NOW + 60_000 };
  const past = { toMillis: () => NOW - 1 };

  it("flags a session owned by a different user as foreign", () => {
    expect(
      classifyExistingSession({ userId: "someone-else", status: "reserved" }, "me", NOW).kind,
    ).toBe("foreign");
  });

  it("succeeded -> already_completed", () => {
    expect(
      classifyExistingSession({ userId: "me", status: "succeeded" }, "me", NOW).kind,
    ).toBe("already_completed");
  });

  it("failed / expired / unknown status -> attempt_closed", () => {
    for (const status of ["failed", "expired", "weird", undefined]) {
      expect(
        classifyExistingSession({ userId: "me", status }, "me", NOW).kind,
      ).toBe("attempt_closed");
    }
  });

  it("reserved + past expiry -> expired", () => {
    expect(
      classifyExistingSession(
        { userId: "me", status: "reserved", expiresAt: past },
        "me",
        NOW,
      ).kind,
    ).toBe("expired");
  });

  it("reserved + future expiry + no PI -> needs_payment_intent", () => {
    expect(
      classifyExistingSession(
        { userId: "me", status: "reserved", expiresAt: future, stripePaymentIntentId: null },
        "me",
        NOW,
      ).kind,
    ).toBe("needs_payment_intent");
  });

  it("reserved + future expiry + PI set -> has_payment_intent", () => {
    const verdict = classifyExistingSession(
      { userId: "me", status: "reserved", expiresAt: future, stripePaymentIntentId: "pi_123" },
      "me",
      NOW,
    );
    expect(verdict).toEqual({ kind: "has_payment_intent", paymentIntentId: "pi_123" });
  });
});

describe("buildReservedSessionDoc", () => {
  it("produces a complete reserved document with the sentinels wired through", () => {
    const EXPIRES = { __expires: true };
    const SERVER_TS = { __serverTimestamp: true };
    const doc = buildReservedSessionDoc({
      userId: "me",
      items: [
        {
          productId: "p1",
          quantity: 2,
          selectedColor: "black",
          selectedSize: null,
          unitPriceRupees: 1000,
          lineTotalRupees: 2000,
          productName: "Chair",
          imagePath: "products/p1/img.jpg",
          imageSource: "network",
        },
      ],
      totals: { subtotal: 2000, deliveryFee: 500, discount: 1000, total: 1500 },
      deliveryAddressSnapshot: { id: "addr_1", fullName: "Me" },
      idempotencyKey: "idem-key-1",
      currency: "pkr",
      amountMinor: 150000,
      expiresAt: EXPIRES,
      serverTimestamp: SERVER_TS,
    });

    expect(doc.status).toBe("reserved");
    expect(doc.stripePaymentIntentId).toBeNull();
    expect(doc.orderId).toBeNull();
    expect(doc.userId).toBe("me");
    expect(doc.total).toBe(1500);
    expect(doc.amountMinor).toBe(150000);
    expect(doc.currency).toBe("pkr");
    expect(doc.idempotencyKey).toBe("idem-key-1");
    expect(doc.expiresAt).toBe(EXPIRES);
    expect(doc.createdAt).toBe(SERVER_TS);
    expect(doc.updatedAt).toBe(SERVER_TS);
  });
});
