import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_object.dart';
import 'package:twin_ar/features/room_ar/marker_ar/viewmodels/marker_ar_viewmodel.dart';
import 'package:twin_ar/features/room_ar/marker_ar/widgets/marker_ar_r10_panel.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_service.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_state.dart';

import 'marker_ar_viewmodel_test.dart' show FakeRoomArMarkerChannel;

class _FakeModelService implements RoomArModelService {
  @override
  Future<RoomArModelState> resolve({
    required String productId,
    required ProductArMetadata metadata,
    void Function(RoomArModelState state)? onState,
  }) async {
    onState?.call(const RoomArModelDownloading(progress: 0.4));
    final ready = RoomArModelReady(
      source: RoomArModelSource.freshDownload,
      file: File('/cache/room_ar_models/x/model.glb'),
    );
    onState?.call(ready);
    return ready;
  }

  @override
  Future<RoomArModelReady?> cachedOnly({
    required String productId,
    required ProductArMetadata metadata,
  }) async => null;

  @override
  Future<void> evictCachedEntry({
    required String productId,
    required ProductArMetadata metadata,
  }) async {}
}

void main() {
  testWidgets(
    'R10 panel opens as a bottom sheet on a small phone with no overflow',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final vm = MarkerArViewModel(channel: FakeRoomArMarkerChannel())
        ..attachModelService(_FakeModelService());
      addTearDown(vm.dispose);
      // Populate history + an active source on every product so the sheet is
      // at its tallest and the button row shows all three actions.
      for (final p in MarkerArObject.values) {
        await vm.r10Resolve(p);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => MarkerArR10Panel.show(context, vm),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Storage model delivery'), findsOneWidget);
      // the sheet never extends above the top of the screen
      final sheetTop = tester.getTopLeft(find.byType(MarkerArR10Panel));
      expect(sheetTop.dy, greaterThanOrEqualTo(0.0));
      // body scrolls: the last product / Done are reachable by scrolling
      await tester.dragUntilVisible(
        find.text('Done'),
        find.byType(SingleChildScrollView),
        const Offset(0, -80),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
