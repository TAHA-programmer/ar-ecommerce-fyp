import { describe, it, expect, vi } from "vitest";

vi.mock("firebase-functions/logger", () => ({
  error: vi.fn(),
  warn: vi.fn(),
  info: vi.fn(),
}));

import {
  mapStripeError,
  errInsufficientStock,
  errUnauthenticated,
} from "../errors";

describe("app error factories", () => {
  it("carry a gRPC code, a stable appCode, and structured details", () => {
    const e = errInsufficientStock("p1", "Chair", 2, 5);
    expect(e.code).toBe("failed-precondition");
    expect((e.details as Record<string, unknown>).appCode).toBe("INSUFFICIENT_STOCK");
    expect((e.details as Record<string, unknown>).available).toBe(2);
    expect((e.details as Record<string, unknown>).requested).toBe(5);
  });

  it("unauthenticated maps to the right grpc code", () => {
    expect(errUnauthenticated().code).toBe("unauthenticated");
  });
});

describe("mapStripeError", () => {
  it("amount_too_small -> PAYMENT_AMOUNT_TOO_SMALL", () => {
    const e = mapStripeError({ type: "StripeInvalidRequestError", code: "amount_too_small" });
    expect((e.details as Record<string, unknown>).appCode).toBe("PAYMENT_AMOUNT_TOO_SMALL");
  });

  it("connection / API / 5xx / 429 -> PAYMENT_PROVIDER_ERROR (unavailable)", () => {
    for (const err of [
      { type: "StripeConnectionError" },
      { type: "StripeAPIError" },
      { statusCode: 500 },
      { statusCode: 429 },
    ]) {
      const e = mapStripeError(err);
      expect(e.code).toBe("unavailable");
      expect((e.details as Record<string, unknown>).appCode).toBe("PAYMENT_PROVIDER_ERROR");
    }
  });

  it("authentication error -> INTERNAL, and never leaks that the key is bad to the client", () => {
    const e = mapStripeError({ type: "StripeAuthenticationError" });
    expect((e.details as Record<string, unknown>).appCode).toBe("INTERNAL");
    expect(e.message.toLowerCase()).not.toContain("key");
    expect(e.message.toLowerCase()).not.toContain("secret");
    expect(e.message.toLowerCase()).not.toContain("auth");
  });

  it("unknown shape -> PAYMENT_PROVIDER_ERROR (safe default)", () => {
    expect((mapStripeError(undefined).details as Record<string, unknown>).appCode).toBe(
      "PAYMENT_PROVIDER_ERROR",
    );
    expect((mapStripeError("boom").details as Record<string, unknown>).appCode).toBe(
      "PAYMENT_PROVIDER_ERROR",
    );
  });

  it("never places a secret-key-like string in the customer-facing error", () => {
    const e = mapStripeError({
      type: "StripeInvalidRequestError",
      message: "sk_test_SHOULD_NEVER_APPEAR order failed",
    });
    const serialised = JSON.stringify({ message: e.message, details: e.details });
    expect(serialised).not.toContain("sk_test_");
  });
});
