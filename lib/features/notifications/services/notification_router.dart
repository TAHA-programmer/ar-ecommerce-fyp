import '../../../app/routes/route_names.dart';
import '../models/app_notification.dart';
import '../models/notification_payload.dart';
import '../models/notification_type.dart';

/// Where a notification takes the user: an existing named route plus its
/// argument. Built ONLY by [NotificationRouter] from a hard-coded table.
class NotificationDestination {
  const NotificationDestination(this.routeName, [this.arguments]);

  final String routeName;
  final Object? arguments;

  @override
  bool operator ==(Object other) =>
      other is NotificationDestination &&
      other.routeName == routeName &&
      other.arguments == arguments;

  @override
  int get hashCode => Object.hash(routeName, arguments);

  @override
  String toString() => 'NotificationDestination($routeName, $arguments)';
}

/// The signed-in identity a notification is checked against.
class NotificationSession {
  const NotificationSession({
    required this.uid,
    required this.isCustomer,
    required this.isSuperAdmin,
  });

  final String? uid;
  final bool isCustomer;
  final bool isSuperAdmin;

  static const signedOut = NotificationSession(
    uid: null,
    isCustomer: false,
    isSuperAdmin: false,
  );
}

/// Pure notification -> destination resolution (plan §4.6, tested as a
/// matrix). Returns `null` (= do nothing) unless EVERY check passes:
///  - the payload already passed [NotificationPayload.tryParse];
///  - a customer type: the user is a signed-in customer AND
///    `recipientUid == uid` (a push for the previous account on a shared
///    device is dropped, never shown to the new user);
///  - an admin type: the user is a signed-in superAdmin;
///  - every entity id the destination needs is present.
/// Routes come from this table - the payload never names a route.
class NotificationRouter {
  NotificationRouter._();

  static NotificationDestination? resolve(
    NotificationPayload payload,
    NotificationSession session,
  ) {
    final uid = session.uid;
    if (uid == null) return null;

    if (payload.type.isAdmin) {
      if (!session.isSuperAdmin) return null;
    } else {
      if (!session.isCustomer || payload.recipientUid != uid) return null;
    }

    switch (payload.type) {
      case NotificationPayloadType.orderPlaced:
      case NotificationPayloadType.orderConfirmed:
      case NotificationPayloadType.orderShipped:
      case NotificationPayloadType.orderDelivered:
      case NotificationPayloadType.orderCancelled:
        final id = payload.orderId;
        return id == null
            ? null
            : NotificationDestination(RouteNames.orderDetail, id);
      case NotificationPayloadType.paymentRefunded:
        return const NotificationDestination(RouteNames.orders);
      case NotificationPayloadType.reviewHidden:
      case NotificationPayloadType.reviewRejected:
      case NotificationPayloadType.reviewRestored:
        return const NotificationDestination(RouteNames.myReviews);
      case NotificationPayloadType.adminNewOrder:
        final id = payload.orderId;
        return id == null
            ? null
            : NotificationDestination(RouteNames.adminOrderDetail, id);
      case NotificationPayloadType.adminLowStock:
      case NotificationPayloadType.adminOutOfStock:
        return const NotificationDestination(RouteNames.adminInventory);
      case NotificationPayloadType.adminReviewFlagged:
        return const NotificationDestination(RouteNames.adminReviews);
      case NotificationPayloadType.adminPaymentIssue:
        return const NotificationDestination(RouteNames.adminNotifications);
    }
  }

  /// Tapping a row in the customer Notification Centre. The row's `route` is
  /// the server's destination ENUM (never a path); anything unrecognised, or
  /// an order row without an entity id, simply doesn't navigate.
  static NotificationDestination? resolveInboxRow(AppNotification n) {
    if (n.type == NotificationType.unknown) return null;
    switch (n.route) {
      case 'orderDetail':
        final id = n.entityId;
        return id == null || id.isEmpty
            ? null
            : NotificationDestination(RouteNames.orderDetail, id);
      case 'orders':
        return const NotificationDestination(RouteNames.orders);
      case 'myReviews':
        return const NotificationDestination(RouteNames.myReviews);
      default:
        return null;
    }
  }
}
