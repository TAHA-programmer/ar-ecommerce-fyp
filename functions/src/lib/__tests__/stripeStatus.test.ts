import { describe, it, expect } from "vitest";

import { classifyPaymentIntentStatus, stockRestoreIsSafe } from "../stripeStatus";

describe("classifyPaymentIntentStatus", () => {
  it("succeeded -> succeeded", () => {
    expect(classifyPaymentIntentStatus("succeeded")).toBe("succeeded");
  });
  it("processing / requires_capture -> in_progress (could still succeed)", () => {
    expect(classifyPaymentIntentStatus("processing")).toBe("in_progress");
    expect(classifyPaymentIntentStatus("requires_capture")).toBe("in_progress");
  });
  it("canceled -> canceled", () => {
    expect(classifyPaymentIntentStatus("canceled")).toBe("canceled");
  });
  it("requires_payment_method / _confirmation / _action -> cancellable", () => {
    for (const s of ["requires_payment_method", "requires_confirmation", "requires_action"]) {
      expect(classifyPaymentIntentStatus(s)).toBe("cancellable");
    }
  });
  it("anything unrecognised -> unknown", () => {
    expect(classifyPaymentIntentStatus("weird")).toBe("unknown");
    expect(classifyPaymentIntentStatus("")).toBe("unknown");
  });
});

describe("stockRestoreIsSafe", () => {
  it("is true ONLY for a terminally-cancelled PaymentIntent", () => {
    expect(stockRestoreIsSafe("canceled")).toBe(true);
    for (const d of ["succeeded", "in_progress", "cancellable", "unknown"] as const) {
      expect(stockRestoreIsSafe(d)).toBe(false);
    }
  });
});
