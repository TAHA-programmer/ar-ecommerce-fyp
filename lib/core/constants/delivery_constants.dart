import '../utils/currency_formatter.dart';
import 'pricing_constants.dart';

/// Single source of truth for delivery-related customer-facing copy.
///
/// Mirrors the server's real, implemented policy so Product Details, the
/// cart and checkout never show a claim the backend doesn't honour:
/// - The delivery fee is a flat [PricingConstants.deliveryFee] on every
///   order — there is no free-delivery threshold anywhere in
///   `CheckoutViewModel` / `functions/src/lib/pricing.ts`. Do not add a
///   "free above Rs X" claim here without first adding that logic there.
/// - The delivery window is [windowStartDays]-[windowEndDays] calendar days
///   from order time, computed server-side in
///   `functions/src/lib/orderFromSession.ts#deliveryWindowMillis` and applied
///   identically to every order regardless of product. A per-product
///   "deliveryEstimate" string can't reflect that shared window, so Product
///   Details reads this constant instead.
class DeliveryConstants {
  DeliveryConstants._();

  /// Matches `DELIVERY_WINDOW_START_DAYS` / `DELIVERY_WINDOW_END_DAYS` in
  /// `functions/src/lib/orderFromSession.ts`.
  static const int windowStartDays = 7;
  static const int windowEndDays = 14;

  /// Pre-checkout estimate shown on Product Details. Deliberately phrased as
  /// a range of days (not "Business Days") since the server computation is
  /// plain calendar-day arithmetic, not business-day aware.
  static const String estimatedDeliveryLabel =
      '$windowStartDays-$windowEndDays Days';

  /// Pre-checkout delivery-fee line, derived from the same
  /// [PricingConstants.deliveryFee] the cart and checkout actually charge.
  /// There is no free-shipping tier — every order is charged the flat fee —
  /// so the copy states the fee instead of advertising a threshold that
  /// doesn't exist.
  static String get deliveryFeeLabel =>
      '${CurrencyFormatter.format(PricingConstants.deliveryFee)} on all orders';
}
