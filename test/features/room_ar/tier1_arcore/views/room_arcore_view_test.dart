import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_object.dart';
import 'package:twin_ar/features/room_ar/marker_ar/room_ar_session_args.dart';
import 'package:twin_ar/features/room_ar/tier1_arcore/models/room_arcore_frame.dart';
import 'package:twin_ar/features/room_ar/tier1_arcore/services/room_arcore_channel.dart';
import 'package:twin_ar/features/room_ar/tier1_arcore/viewmodels/room_arcore_viewmodel.dart';
import 'package:twin_ar/features/room_ar/tier1_arcore/views/room_arcore_view.dart';

/// Mocks the `permission_handler` platform channel (mirrors
/// marker_ar_view_test.dart's `_PermissionMock` — camera-granted by default).
class _PermissionMock {
  static const _channel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );

  /// PermissionStatus index: 0 denied, 1 granted, 2 restricted, 4 permanently denied.
  static int status = 1;

  static void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'checkPermissionStatus':
              return status;
            case 'requestPermissions':
              final perms = (call.arguments as List).cast<int>();
              return {for (final p in perms) p: status};
            case 'checkServiceStatus':
              return 1;
            default:
              return null;
          }
        });
  }

  static void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

class _FakeChannel implements RoomArCoreChannel {
  final _events = StreamController<RoomArCoreFrame>.broadcast();
  final List<String> calls = [];

  @override
  Stream<RoomArCoreFrame> frames() => _events.stream;
  @override
  Future<void> setObject(String mode) async => calls.add('setObject:$mode');
  @override
  Future<void> setExternalModel(String mode, String? p) async =>
      calls.add('setExternalModel:$mode');
  @override
  Future<void> placeAt(double fx, double fy) async => calls.add('placeAt');
  @override
  Future<void> beginReposition() async => calls.add('beginReposition');
  @override
  Future<void> repositionTo(double fx, double fy) async =>
      calls.add('repositionTo');
  @override
  Future<void> endReposition() async => calls.add('endReposition');
  @override
  Future<void> setYaw(double degrees) async => calls.add('setYaw');
  @override
  Future<void> resetPlacement() async => calls.add('resetPlacement');
  @override
  Future<void> setActive(bool active) async => calls.add('setActive:$active');

  /// Pushes a frame directly onto the stream this fake serves — used to put
  /// the ViewModel into `hasAnchor: true` for drag/rotate/reset tests
  /// without needing a real native anchor.
  void pushFrame(RoomArCoreFrame f) => _events.add(f);

  Future<void> close() => _events.close();
}

const _placedFrame = RoomArCoreFrame(
  tracking: true,
  trackingFailureReason: 'NONE',
  planesFound: true,
  hasAnchor: true,
  anchorTracking: true,
  justPlaced: true,
  reticleVisible: false,
);

RoomArSessionArgs _argsFor(MarkerArObject o) => RoomArSessionArgs(
  firestoreProductId: o.firestoreProductId,
  object: o,
  metadata: ProductArMetadata(
    storagePath: 'products/${o.firestoreProductId}/ar/model-v1.glb',
    modelVersion: '1',
    sha256: 'a' * 64,
    widthM: 0.5,
    depthM: 0.5,
    heightM: 0.5,
  ),
  productTitle: o.displayName,
);

RoomArSessionArgs _genericArgs(String productId, String title) =>
    RoomArSessionArgs(
      firestoreProductId: productId,
      object: null,
      metadata: ProductArMetadata(
        storagePath: 'products/$productId/ar/model-v1.glb',
        modelVersion: '1',
        sha256: 'b' * 64,
        widthM: 0.5,
        depthM: 0.5,
        heightM: 0.5,
      ),
      productTitle: title,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeChannel channel;

  setUp(() {
    _PermissionMock.status = 1; // granted
    _PermissionMock.install();
    channel = _FakeChannel();
  });

  tearDown(() async {
    _PermissionMock.remove();
    await channel.close();
  });

  Widget harness(RoomArSessionArgs args) => MaterialApp(
    home: ChangeNotifierProvider(
      create: (_) => RoomArCoreViewModel(args: args, channel: channel)..start(),
      child: const RoomArCoreView(),
    ),
    // The "Prefer a 3D preview instead?" link navigates to a real named
    // route — stubbed here so tapping it in a test doesn't crash on an
    // unregistered route (the real app registers this via its router).
    routes: {RouteNames.roomArPreview: (_) => const SizedBox()},
  );

  group('RoomArCoreView — PlatformView creation-time model selection '
      '(regression: a post-creation setObject() channel call races the '
      "PlatformView's own creation and is silently dropped, leaving the "
      'renderer showing nothing at all — the exact bug class already fixed '
      "once for Tier 3's R16 admin preview)", () {
    testWidgets(
      'a bundled product opens on its own mode via creationParams, never '
      'the default "chair"',
      (tester) async {
        for (final (obj, mode) in const [
          (MarkerArObject.table, 'table'),
          (MarkerArObject.lamp, 'lamp'),
          (MarkerArObject.sofa, 'sofa'),
          (MarkerArObject.chair, 'chair'),
        ]) {
          await tester.pumpWidget(harness(_argsFor(obj)));
          await tester.pump();
          final av = tester.widget<ArCorePlatformView>(
            find.byType(ArCorePlatformView),
          );
          expect(
            av.mode,
            mode,
            reason: '$obj must open its own model, not the default chair',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        }
      },
    );

    testWidgets('a coverage-expansion / future Admin product opens on its own '
        'Firestore product id via creationParams', (tester) async {
      await tester.pumpWidget(
        harness(_genericArgs('velvet-armchair', 'Velvet Armchair')),
      );
      await tester.pump();
      final av = tester.widget<ArCorePlatformView>(
        find.byType(ArCorePlatformView),
      );
      expect(av.mode, 'velvet-armchair');
    });
  });

  group('RoomArCoreView — raw-pointer interaction layer (regression: §31 '
      'paired a dedicated TapGestureRecognizer with the existing '
      'ScaleGestureRecognizer, reasoning Tap would win a clean tap and '
      'Scale would win a real drag. The next physical test disproved that: '
      '`tapDown` climbed reliably but `tapsSent` stayed 0 — Tap never won. '
      "Traced to Flutter's actual gesture-arena source: "
      '`BaseTapGestureRecognizer` (tap.dart) only ever wins by being the '
      'LAST member standing; `ScaleGestureRecognizer` (scale.dart) '
      'proactively self-accepts the instant movement crosses its own small '
      'slop, which ordinary finger-contact jitter does on almost every '
      'real touch; and `GestureArenaManager._resolve` (arena.dart) shows '
      'that once the arena is closed, ANY member\'s proactive accept '
      'immediately rejects every other member — so Scale wins almost every '
      'real tap, not just genuine drags. Fixed by dropping the gesture-'
      'arena/recognizer system for this widget entirely: a `Listener` with '
      'hand-tracked raw pointer events, per the class-level doc comment in '
      'room_arcore_view.dart. These tests dispatch REAL pointer sequences '
      'via `tester.startGesture` (down/move/up/cancel) through the actual '
      'widget tree — not by invoking callback objects directly — since a '
      '`Listener` (unlike forwarding into an embedded AndroidView\'s own '
      'native touch handling) participates in ordinary Flutter hit-testing '
      'that the widget-test harness renders faithfully.', () {
    Offset center(WidgetTester tester) =>
        tester.getCenter(find.byKey(placementGestureDetectorKey));

    testWidgets(
      'a clean one-finger down/up sends exactly one placeAt on the first '
      'valid tap — no drag, hold, or multi-finger needed',
      (tester) async {
        await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
        await tester.pump();
        final gesture = await tester.startGesture(center(tester));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(channel.calls.where((c) => c == 'placeAt').length, 1);
      },
    );

    testWidgets(
      'natural small finger jitter under the tap-slop threshold still '
      'counts as exactly one tap',
      (tester) async {
        await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
        await tester.pump();
        final gesture = await tester.startGesture(center(tester));
        await tester.pump();
        // Well under RoomArCoreViewModel.tapSlopPx (18px).
        await gesture.moveBy(const Offset(4, 3));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(channel.calls.where((c) => c == 'placeAt').length, 1);
      },
    );

    testWidgets(
      'genuine large movement before anything is placed never places',
      (tester) async {
        await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
        await tester.pump();
        final gesture = await tester.startGesture(center(tester));
        await tester.pump();
        await gesture.moveBy(const Offset(60, 60)); // well over the slop
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(channel.calls, isNot(contains('placeAt')));
      },
    );

    testWidgets('a second pointer touching down permanently rules out initial '
        'placement for the whole sequence, even if both lift cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
      await tester.pump();
      final c = center(tester);
      final g1 = await tester.startGesture(c);
      await tester.pump();
      final g2 = await tester.startGesture(c + const Offset(30, 0));
      await tester.pump();
      await g1.up();
      await tester.pump();
      await g2.up();
      await tester.pump();
      expect(channel.calls, isNot(contains('placeAt')));
    });

    testWidgets('a cancelled pointer produces no placement', (tester) async {
      await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
      await tester.pump();
      final gesture = await tester.startGesture(center(tester));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();
      expect(channel.calls, isNot(contains('placeAt')));
    });

    testWidgets(
      'once placed, a real single-finger drag repositions continuously and '
      'never re-places on release',
      (tester) async {
        await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
        await tester.pump();
        channel.pushFrame(_placedFrame);
        await tester.pump();
        final gesture = await tester.startGesture(center(tester));
        await tester.pump();
        await gesture.moveBy(const Offset(50, 0)); // exceeds the slop
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(channel.calls, contains('beginReposition'));
        expect(channel.calls, contains('repositionTo'));
        expect(channel.calls, contains('endReposition'));
        expect(channel.calls, isNot(contains('placeAt')));
      },
    );

    testWidgets('once placed, a discrete tap elsewhere (no real movement) '
        'repositions via placeAt — a superset of, not a contradiction of, '
        '"drag repositions"', (tester) async {
      await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
      await tester.pump();
      channel.pushFrame(_placedFrame);
      await tester.pump();
      final gesture = await tester.startGesture(center(tester));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(channel.calls.where((c) => c == 'placeAt').length, 1);
    });

    testWidgets(
      'two fingers, any time, drive rotate via setYaw — never placeAt, '
      'even once something is already placed',
      (tester) async {
        await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
        await tester.pump();
        channel.pushFrame(_placedFrame);
        await tester.pump();
        final c = center(tester);
        final g1 = await tester.startGesture(c - const Offset(20, 0));
        await tester.pump();
        final g2 = await tester.startGesture(c + const Offset(20, 0));
        await tester.pump();
        await g1.moveBy(const Offset(0, -12));
        await g2.moveBy(const Offset(0, 12));
        await tester.pump();
        await g1.up();
        await tester.pump();
        await g2.up();
        await tester.pump();
        expect(channel.calls, contains('setYaw'));
        expect(channel.calls, isNot(contains('placeAt')));
      },
    );

    testWidgets('the Reset button removes the placement independently of the '
        'pointer layer', (tester) async {
      await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
      await tester.pump();
      channel.pushFrame(_placedFrame);
      await tester.pump();
      await tester.tap(find.text('Remove / reset placement'));
      await tester.pump();
      expect(channel.calls, contains('resetPlacement'));
    });

    testWidgets(
      'top-chrome controls (back button) remain clickable and never leak '
      'into placement',
      (tester) async {
        await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
        await tester.pump();
        expect(channel.calls, isNot(contains('placeAt')));
      },
    );

    testWidgets(
      'bottom-chrome controls ("Prefer a 3D preview") remain clickable and '
      'never leak into placement',
      (tester) async {
        await tester.pumpWidget(harness(_argsFor(MarkerArObject.chair)));
        await tester.pump();
        await tester.tap(find.text('Prefer a 3D preview instead?'));
        await tester.pumpAndSettle();
        expect(channel.calls, isNot(contains('placeAt')));
      },
    );
  });
}
