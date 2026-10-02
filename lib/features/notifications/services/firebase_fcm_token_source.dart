import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'fcm_token_source.dart';

/// Real [FcmTokenSource]. `FirebaseMessaging.instance` is resolved on first
/// use (not at construction): the provider tree can build services in tests
/// and `Firebase.initializeApp()` must have run before the singleton is
/// touched. No `onMessage` / `getInitialMessage` listeners are attached here
/// - message handling and tap routing belong to Stage S5.
class FirebaseFcmTokenSource implements FcmTokenSource {
  FirebaseFcmTokenSource({FirebaseMessaging? messaging})
    : _injected = messaging;

  final FirebaseMessaging? _injected;

  FirebaseMessaging get _messaging => _injected ?? FirebaseMessaging.instance;

  @override
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('FcmTokenSource.getToken failed: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('FcmTokenSource.deleteToken failed: ${e.runtimeType}');
    }
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}
