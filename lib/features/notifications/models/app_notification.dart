import 'package:cloud_firestore/cloud_firestore.dart';

import 'notification_type.dart';

/// One row of the customer notification inbox
/// (`users/{uid}/notifications/{dedupeKey}`, written only by Cloud Functions).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.route,
    required this.entityId,
    required this.createdAt,
    required this.readAt,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;

  /// Server destination enum (`orderDetail`, `orders`, `myReviews`) - never a
  /// path. Mapped to a real route by `NotificationRouter`.
  final String route;
  final String? entityId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    route: route,
    entityId: entityId,
    createdAt: createdAt,
    readAt: readAt ?? this.readAt,
  );

  /// Defensive mapping (every other mapper in this codebase is): wrong-typed
  /// fields degrade to safe defaults instead of throwing. A pending
  /// `serverTimestamp` (null `createdAt` in a local snapshot) reads as "now".
  factory AppNotification.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    String str(dynamic v) => v is String ? v : '';
    return AppNotification(
      id: id,
      type: NotificationType.fromWire(str(data['type'])),
      title: str(data['title']),
      body: str(data['body']),
      route: str(data['route']),
      entityId: data['entityId'] is String ? data['entityId'] as String : null,
      createdAt: ts(data['createdAt']) ?? DateTime.now(),
      readAt: ts(data['readAt']),
    );
  }
}
