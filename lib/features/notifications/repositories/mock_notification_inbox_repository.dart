import '../models/app_notification.dart';
import 'notification_inbox_repository.dart';

/// In-memory [NotificationInboxRepository] for widget/unit tests. Mirrors the
/// real contract: newest first, a 50-row window, mark-read/delete mutate and
/// notify, and failures are simulated with [failWrites].
class MockNotificationInboxRepository extends NotificationInboxRepository {
  MockNotificationInboxRepository({
    List<AppNotification> initial = const [],
    this._isLoading = false,
    this._hasError = false,
  }) : _items = List.of(initial) {
    _sort();
  }

  List<AppNotification> _items;
  bool _isLoading;
  bool _hasError;

  /// When true, every write returns `false` and changes nothing.
  bool failWrites = false;
  int retryCount = 0;

  void _sort() => _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void setItems(List<AppNotification> items) {
    _items = List.of(items);
    _sort();
    _isLoading = false;
    _hasError = false;
    notifyListeners();
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void setError(bool value) {
    _hasError = value;
    _isLoading = false;
    notifyListeners();
  }

  @override
  bool get isLoading => _isLoading;

  @override
  bool get hasError => _hasError;

  @override
  List<AppNotification> get notifications =>
      List.unmodifiable(_items.take(NotificationInboxRepository.windowSize));

  @override
  void retry() {
    retryCount++;
    _hasError = false;
    notifyListeners();
  }

  @override
  Future<bool> markRead(String notificationId) async {
    if (failWrites) return false;
    final i = _items.indexWhere((n) => n.id == notificationId);
    if (i < 0) return false;
    _items[i] = _items[i].copyWith(readAt: DateTime.now());
    notifyListeners();
    return true;
  }

  @override
  Future<bool> markAllRead() async {
    if (failWrites) return false;
    _items = [
      for (final n in _items)
        n.isUnread ? n.copyWith(readAt: DateTime.now()) : n,
    ];
    notifyListeners();
    return true;
  }

  @override
  Future<bool> delete(String notificationId) async {
    if (failWrites) return false;
    _items.removeWhere((n) => n.id == notificationId);
    notifyListeners();
    return true;
  }
}
