import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_object.dart';
import 'package:twin_ar/features/room_ar/preview/room_ar_preview_channel.dart';
import 'package:twin_ar/features/room_ar/preview/room_ar_preview_view.dart';
import 'package:twin_ar/features/room_ar/preview/room_ar_preview_viewmodel.dart';

import 'room_ar_preview_viewmodel_test.dart' show argsFor;

// Reuse the fake channel shape from the viewmodel test file is not exported;
// declare a minimal local one.
class _Channel implements RoomArPreviewChannel {
  final calls = <String>[];
  @override
  Stream<RoomArPreviewLoad> loadStates() =>
      Stream.value(RoomArPreviewLoad.ready);
  @override
  Future<void> setModel(String mode, String? p) async => calls.add('setModel');
  @override
  Future<void> orbit(double dx, double dy) async => calls.add('orbit');
  @override
  Future<void> pan(double dx, double dy) async => calls.add('pan');
  @override
  Future<void> zoom(double s) async => calls.add('zoom');
  @override
  Future<void> resetView() async => calls.add('reset');
  @override
  Future<void> setActive(bool a) async => calls.add('setActive:$a');
}

void main() {
  late _Channel channel;

  setUp(() => channel = _Channel());

  Widget harness(MarkerArObject o) => MaterialApp(
    home: ChangeNotifierProvider(
      create: (_) =>
          RoomArPreviewViewModel(args: argsFor(o), channel: channel)..start(),
      child: const RoomArPreviewView(),
    ),
  );

  testWidgets('the PlatformView starts on the opened product\'s model '
      '(creationParams carry its mode, not the default chair)', (tester) async {
    for (final (obj, mode) in const [
      (MarkerArObject.chair, 'chair'),
      (MarkerArObject.table, 'table'),
      (MarkerArObject.lamp, 'lamp'),
      (MarkerArObject.sofa, 'sofa'),
    ]) {
      await tester.pumpWidget(harness(obj));
      await tester.pump();
      final av = tester.widget<AndroidView>(find.byType(AndroidView));
      expect(
        (av.creationParams as Map)['mode'],
        mode,
        reason: '$obj must open its own model',
      );
      await tester.pumpWidget(const SizedBox()); // dispose between iterations
      await tester.pump();
    }
  });

  testWidgets('is clearly a 3D preview, product-specific, no dev controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness(MarkerArObject.sofa));
    await tester.pumpAndSettle();

    expect(find.text('Luna Right-Chaise Sectional Sofa'), findsOneWidget);
    expect(find.textContaining('Interactive 3D preview'), findsOneWidget);
    expect(find.textContaining('not camera AR'), findsOneWidget);
    expect(find.text('Reset view'), findsOneWidget);
    expect(find.textContaining('actual size'), findsOneWidget);
    // no developer/debug affordances
    expect(find.byIcon(Icons.bug_report), findsNothing);
    expect(find.byIcon(Icons.bug_report_outlined), findsNothing);
    expect(find.byIcon(Icons.cloud_download_outlined), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag orbits and "Reset view" resets the renderer', (
    tester,
  ) async {
    await tester.pumpWidget(harness(MarkerArObject.chair));
    await tester.pumpAndSettle();

    final g = await tester.startGesture(
      tester.getCenter(find.byType(AndroidView)),
    );
    await g.moveBy(const Offset(30, 0));
    await g.moveBy(const Offset(30, 0));
    await g.moveBy(const Offset(30, 0));
    await g.up();
    await tester.pump(
      const Duration(milliseconds: 400),
    ); // clear double-tap timer
    expect(channel.calls, contains('orbit'));

    await tester.tap(find.text('Reset view'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(channel.calls, contains('reset'));
  });

  testWidgets('back button pops the route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider(
                      create: (_) => RoomArPreviewViewModel(
                        args: argsFor(MarkerArObject.lamp),
                        channel: channel,
                      )..start(),
                      child: const RoomArPreviewView(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AndroidView), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.byType(AndroidView), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
