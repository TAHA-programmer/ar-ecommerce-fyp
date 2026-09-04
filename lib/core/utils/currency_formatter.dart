import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _formatter = NumberFormat('#,##0.##', 'en_US');

  /// Formats an amount to a string like 'Rs 10,000' or 'Rs 24,580.5'
  static String format(num amount) {
    // If it's a whole number, format without decimals.
    // Otherwise, NumberFormat('#,##0.##') will include up to 2 decimals.
    return 'Rs ${_formatter.format(amount)}';
  }
}
