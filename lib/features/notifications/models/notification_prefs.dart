/// Per-user PUSH preferences (`users/{uid}/notificationSettings/prefs`).
///
/// Every switch defaults ON - the server treats a missing key (or a missing
/// doc) as ON and only an explicit `false` as opt-out (D7: any category,
/// including order updates, may be turned off; the inbox keeps recording
/// regardless). The four admin switches are only ever written for a
/// superAdmin (Firestore rules reject them otherwise).
class NotificationPrefs {
  const NotificationPrefs({
    this.pushOrders = true,
    this.pushReviews = true,
    this.pushAdminOrders = true,
    this.pushAdminStock = true,
    this.pushAdminModeration = true,
    this.pushAdminPayments = true,
  });

  final bool pushOrders;
  final bool pushReviews;
  final bool pushAdminOrders;
  final bool pushAdminStock;
  final bool pushAdminModeration;
  final bool pushAdminPayments;

  NotificationPrefs copyWith({
    bool? pushOrders,
    bool? pushReviews,
    bool? pushAdminOrders,
    bool? pushAdminStock,
    bool? pushAdminModeration,
    bool? pushAdminPayments,
  }) => NotificationPrefs(
    pushOrders: pushOrders ?? this.pushOrders,
    pushReviews: pushReviews ?? this.pushReviews,
    pushAdminOrders: pushAdminOrders ?? this.pushAdminOrders,
    pushAdminStock: pushAdminStock ?? this.pushAdminStock,
    pushAdminModeration: pushAdminModeration ?? this.pushAdminModeration,
    pushAdminPayments: pushAdminPayments ?? this.pushAdminPayments,
  );

  /// Only an explicit boolean `false` turns a switch off (mirrors the server).
  factory NotificationPrefs.fromMap(Map<String, dynamic>? data) {
    bool on(String key) => data?[key] != false;
    return NotificationPrefs(
      pushOrders: on('pushOrders'),
      pushReviews: on('pushReviews'),
      pushAdminOrders: on('pushAdminOrders'),
      pushAdminStock: on('pushAdminStock'),
      pushAdminModeration: on('pushAdminModeration'),
      pushAdminPayments: on('pushAdminPayments'),
    );
  }

  /// The keys to WRITE for a role. A customer never writes `pushAdmin*` (the
  /// rules would reject the whole write); an admin writes only the admin
  /// keys (their customer switches are irrelevant - the server never sends
  /// customer pushes to an admin-stamped device).
  Map<String, bool> toMap({required bool isAdmin}) => isAdmin
      ? {
          'pushAdminOrders': pushAdminOrders,
          'pushAdminStock': pushAdminStock,
          'pushAdminModeration': pushAdminModeration,
          'pushAdminPayments': pushAdminPayments,
        }
      : {'pushOrders': pushOrders, 'pushReviews': pushReviews};

  @override
  bool operator ==(Object other) =>
      other is NotificationPrefs &&
      other.pushOrders == pushOrders &&
      other.pushReviews == pushReviews &&
      other.pushAdminOrders == pushAdminOrders &&
      other.pushAdminStock == pushAdminStock &&
      other.pushAdminModeration == pushAdminModeration &&
      other.pushAdminPayments == pushAdminPayments;

  @override
  int get hashCode => Object.hash(
    pushOrders,
    pushReviews,
    pushAdminOrders,
    pushAdminStock,
    pushAdminModeration,
    pushAdminPayments,
  );
}
