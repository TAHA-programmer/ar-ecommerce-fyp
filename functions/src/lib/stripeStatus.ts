/**
 * Classify a Stripe PaymentIntent `status` into what the expired-reservation
 * sweep (and the hardened `payment_failed` path) may safely do.
 *
 * The governing rule (Phase 8.13.4 point 2): **stock is only ever restored
 * when the PaymentIntent can no longer succeed.** Anything that could still
 * become `succeeded` is deferred, never restored.
 *
 * Pure (no imports).
 */
export type PaymentIntentDisposition =
  | "succeeded" //  terminal-paid  -> finalize the order; NEVER restore
  | "in_progress" //  processing / requires_capture -> could still succeed -> DEFER
  | "canceled" //  terminal-unpaid -> restore is safe
  | "cancellable" //  requires_payment_method / _confirmation / _action -> cancel THEN restore
  | "unknown"; //  unrecognised -> DEFER (never restore)

export function classifyPaymentIntentStatus(status: string): PaymentIntentDisposition {
  switch (status) {
    case "succeeded":
      return "succeeded";
    case "processing":
    case "requires_capture":
      return "in_progress";
    case "canceled":
      return "canceled";
    case "requires_payment_method":
    case "requires_confirmation":
    case "requires_action":
      return "cancellable";
    default:
      return "unknown";
  }
}

/**
 * `true` only when restoring stock is definitely safe: the PaymentIntent is
 * in a terminal state from which it can never become `succeeded`. Being
 * `cancellable` is NOT safe on its own - it must be cancelled first and the
 * cancellation confirmed.
 */
export function stockRestoreIsSafe(disposition: PaymentIntentDisposition): boolean {
  return disposition === "canceled";
}
