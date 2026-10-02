import 'dart:async';

import 'fcm_message_source.dart';

/// Test double for [FcmMessageSource].
class MockFcmMessageSource implements FcmMessageSource {
  MockFcmMessageSource({this.initial});

  IncomingPushMessage? initial;
  final _opened = StreamController<IncomingPushMessage>.broadcast();
  final _foreground = StreamController<IncomingPushMessage>.broadcast();

  void emitOpened(IncomingPushMessage m) => _opened.add(m);
  void emitForeground(IncomingPushMessage m) => _foreground.add(m);

  Future<void> dispose() async {
    await _opened.close();
    await _foreground.close();
  }

  @override
  Future<IncomingPushMessage?> initialMessage() async => initial;

  @override
  Stream<IncomingPushMessage> get onMessageOpenedApp => _opened.stream;

  @override
  Stream<IncomingPushMessage> get onForegroundMessage => _foreground.stream;
}
