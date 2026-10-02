import 'dart:async';

import 'fcm_token_source.dart';

/// Test double for [FcmTokenSource].
class MockFcmTokenSource implements FcmTokenSource {
  MockFcmTokenSource({this.token});

  String? token;
  int deleteCount = 0;
  int getCount = 0;
  final StreamController<String> _refresh =
      StreamController<String>.broadcast();

  /// Simulates FCM rotating the token.
  void emitRefresh(String newToken) {
    token = newToken;
    _refresh.add(newToken);
  }

  Future<void> dispose() => _refresh.close();

  @override
  Future<String?> getToken() async {
    getCount++;
    return token;
  }

  @override
  Future<void> deleteToken() async {
    deleteCount++;
    token = null;
  }

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;
}
