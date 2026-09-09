/**
 * Stripe smallest-currency-unit conversion.
 *
 * TWin AR prices are whole rupees (`ProductModel.priceAmount` is an `int`,
 * `Rs` == PKR - see the reference pack Decisions Log). Stripe charge amounts
 * must be given as an integer in the currency's smallest unit. PKR is a
 * standard two-decimal currency and is NOT on Stripe's zero-decimal list, so
 * PKR 500 -> 50000 (paisa).
 *
 * This module is pure (no imports, no Firebase) so it is trivially testable
 * and reusable by every later Phase 8.13 subphase.
 */

/**
 * Currencies Stripe treats as zero-decimal: the amount you pass IS already
 * the smallest unit (no x100). Source: Stripe "Zero-decimal currencies".
 * PKR is deliberately absent.
 */
export const STRIPE_ZERO_DECIMAL_CURRENCIES: ReadonlySet<string> = new Set([
  "bif",
  "clp",
  "djf",
  "gnf",
  "jpy",
  "kmf",
  "krw",
  "mga",
  "pyg",
  "rwf",
  "ugx",
  "vnd",
  "vuv",
  "xaf",
  "xof",
  "xpf",
]);

/**
 * Hard upper bound on any single Stripe amount this app will ever send, in
 * minor units. Mirrors the 10,000,000-rupee ceiling enforced on every
 * monetary field in `firestore.rules` (10,000,000 rupees == 1,000,000,000
 * paisa), well within `Number.MAX_SAFE_INTEGER`.
 */
export const MAX_STRIPE_MINOR_UNITS = 10_000_000 * 100;

/**
 * Convert a major-unit amount (e.g. whole rupees) to the integer smallest
 * currency unit Stripe expects.
 *
 * Throws - never returns a bad number - on a non-finite, negative,
 * over-ceiling, or non-integer-after-conversion input, so a malformed amount
 * can never reach `stripe.paymentIntents.create`.
 */
export function toStripeMinorUnits(majorAmount: number, currency: string): number {
  if (typeof majorAmount !== "number" || !Number.isFinite(majorAmount) || majorAmount < 0) {
    throw new Error(`toStripeMinorUnits: invalid amount for ${currency}: ${majorAmount}`);
  }
  const code = currency.trim().toLowerCase();
  if (code.length === 0) {
    throw new Error("toStripeMinorUnits: empty currency code");
  }
  const factor = STRIPE_ZERO_DECIMAL_CURRENCIES.has(code) ? 1 : 100;
  const minor = Math.round(majorAmount * factor);
  if (!Number.isInteger(minor) || minor < 0 || minor > MAX_STRIPE_MINOR_UNITS) {
    throw new Error(
      `toStripeMinorUnits: ${currency} amount ${majorAmount} -> ${minor} is out of the allowed range`,
    );
  }
  return minor;
}
