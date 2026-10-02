import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'fcm_message_source.dart';

/// Real [FcmMessageSource]. `FirebaseMessaging.instance` is resolved lazily.
/// No `onBackgroundMessage` handler is registered (plan §4.5: we send
/// `notification` + `data` messages, the OS renders them, and the inbox is
/// server-written, so there is nothing to persist in a headless isolate).
class FirebaseFcmMessageSource implements FcmMessageSource {
  FirebaseFcmMessageSource({FirebaseMessaging? messaging})
    : _injected = messaging;

  final FirebaseMessaging? _injected;

  FirebaseMessaging get _messaging => _injected ?? FirebaseMessaging.instance;

  static IncomingPushMessage _map(RemoteMessage m) => IncomingPushMessage(
    data: Map<String, dynamic>.from(m.data),
    title: m.notification?.title,
    body: m.notification?.body,
  );

  @override
  Future<IncomingPushMessage?> initialMessage() async {
    try {
      final m = await _messaging.getInitialMessage();
      return m == null ? null : _map(m);
    } catch (e) {
      debugPrint('FcmMessageSource.initialMessage failed: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Stream<IncomingPushMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_map);

  @override
  Stream<IncomingPushMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_map);
}
