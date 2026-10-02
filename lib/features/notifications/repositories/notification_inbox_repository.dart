import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';

/// The signed-in CUSTOMER's notification inbox: a live view of the 50 newest
/// `users/{uid}/notifications` rows plus mark-read / delete. One instance is
/// provided app-wide (like favorites/cart) so the header bell badge and the
/// Notification Centre screen read the same state.
///
/// There is deliberately no unread COUNTER field: [unreadCount] is derived
/// from the loaded window, so nothing can drift and the server never writes
/// on a read. Admin has no inbox (plan §4.2) - for an admin session this is
/// permanently empty and idle.
abstract class NotificationInboxRepository extends ChangeNotifier {
  /// How many rows are loaded (and therefore the most unread we can count).
  static const int windowSize = 50;

  /// `true` until the first snapshot (or error) for the current user.
  bool get isLoading;

  /// A transient error for the CURRENT user. The last-known list is kept
  /// (never silently looks like "no notifications").
  bool get hasError;

  /// Newest first.
  List<AppNotification> get notifications;

  /// Unread rows in the loaded window.
  int get unreadCount => notifications.where((n) => n.isUnread).length;

  /// Re-subscribes after an error.
  void retry();

  /// Marks one row read. Throws nothing the UI must handle: a failure leaves
  /// the row unread and returns `false`.
  Future<bool> markRead(String notificationId);

  /// Marks every currently-unread loaded row read in one batch.
  Future<bool> markAllRead();

  /// Dismisses (deletes) one row.
  Future<bool> delete(String notificationId);
}
