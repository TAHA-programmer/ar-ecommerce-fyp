import 'notification_type.dart';

/// A parsed, VALIDATED FCM data payload (plan §4.6). [tryParse] returns
/// `null` for anything that is not exactly the documented shape, and the app
/// then ignores the message (no navigation, no banner).
class NotificationPayload {
  const NotificationPayload({
    required this.type,
    required this.recipientUid,
    this.orderId,
    this.reviewId,
    this.productId,
    this.notificationId,
  });

  final NotificationPayloadType type;

  /// Customer pushes only; the app re-checks it against the signed-in user
  /// (a push meant for the previous account on a shared device is dropped).
  final String? recipientUid;
  final String? orderId;
  final String? reviewId;
  final String? productId;
  final String? notificationId;

  static const String supportedVersion = '1';
  static final RegExp _id = RegExp(r'^[A-Za-z0-9_.:-]{1,200}$');

  static String? _checked(Object? raw) {
    if (raw == null) return null;
    if (raw is! String || !_id.hasMatch(raw)) throw const FormatException();
    return raw;
  }

  /// Strict parse. Unknown version, unknown type, an audience that disagrees
  /// with the type, a customer payload without `recipientUid`, or any id that
  /// fails the shape check => `null`.
  static NotificationPayload? tryParse(Map<String, dynamic>? data) {
    if (data == null) return null;
    try {
      if (data['v'] != supportedVersion) return null;
      final type = NotificationPayloadType.tryParse(data['type'] as String?);
      if (type == null) return null;

      final audience = data['audience'];
      if (audience != (type.isAdmin ? 'admin' : 'customer')) return null;

      final recipientUid = _checked(data['recipientUid']);
      if (!type.isAdmin && recipientUid == null) return null;

      return NotificationPayload(
        type: type,
        recipientUid: type.isAdmin ? null : recipientUid,
        orderId: _checked(data['orderId']),
        reviewId: _checked(data['reviewId']),
        productId: _checked(data['productId']),
        notificationId: _checked(data['notificationId']),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
