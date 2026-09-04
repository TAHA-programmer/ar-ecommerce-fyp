import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_config.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_object.dart';
import 'package:twin_ar/features/room_ar/marker_ar/viewmodels/marker_ar_viewmodel.dart';
import 'package:twin_ar/features/room_ar/marker_ar/views/marker_ar_view.dart';
import 'package:twin_ar/features/room_ar/room_ar_product_manifest.dart';

import 'marker_ar_viewmodel_test.dart' show FakeRoomArMarkerChannel;

/// Mocks the `permission_handler` platform channel.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRoomArMarkerChannel channel;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _PermissionMock.status = 1; // granted
    _PermissionMock.install();
    channel = FakeRoomArMarkerChannel();
  });

  tearDown(() async {
    _PermissionMock.remove();
    await channel.close();
  });

  Widget harness() => MaterialApp(
    home: ChangeNotifierProvider(
      create: (_) => MarkerArViewModel(channel: channel)..start(),
      child: const MarkerArView(),
    ),
  );

  // Infinix Hot 40 — 1080 px / ~2.75 dpr ≈ 393 dp wide; the tight sweep uses a
  // deliberately narrower/shorter box to stress the chrome.
  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'camera-denied shows the themed permission request, not the camera',
    (tester) async {
      _PermissionMock.status = 0; // denied
      await setViewport(tester, const Size(393, 851));
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('Camera access needed'), findsOneWidget);
      expect(find.text('Allow camera'), findsOneWidget);
      expect(find.byType(AndroidView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('permanently-denied offers app settings', (tester) async {
    _PermissionMock.status = 4;
    await setViewport(tester, const Size(393, 851));
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'camera-granted renders the AR surface + honest chrome with no overflow at '
    'the Infinix viewport',
    (tester) async {
      await setViewport(tester, const Size(393, 851));
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.byType(AndroidView), findsOneWidget);
      // honest "searching" chrome before any frame
      expect(find.textContaining('printed marker'), findsWidgets);
      // all four products are reachable in the selector
      for (final o in [
        MarkerArObject.chair,
        MarkerArObject.table,
        MarkerArObject.lamp,
        MarkerArObject.sofa,
      ]) {
        expect(
          find.byKey(ValueKey('marker-ar-object-${o.name}')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching objects and opening calibration never overflows', (
    tester,
  ) async {
    await setViewport(tester, const Size(360, 690)); // deliberately tight
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    for (final name in ['table', 'lamp', 'sofa', 'chair']) {
      final chip = find.byKey(ValueKey('marker-ar-object-$name'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow on $name');
    }

    await tester.tap(find.byIcon(Icons.straighten));
    await tester.pumpAndSettle();
    expect(find.text('Marker size & scale'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('object selection drives the ViewModel + native mode', (
    tester,
  ) async {
    await setViewport(tester, const Size(393, 851));
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final chip = find.byKey(const ValueKey('marker-ar-object-sofa'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pump();
    expect(channel.lastObject, MarkerArObject.sofa);
  });

  group('customer mode (R15/R17)', () {
    Widget customerHarness(MarkerArObject object) => MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => MarkerArViewModel(
          channel: channel,
          mode: MarkerArLaunchMode.customerProduct,
          initialObject: object,
          customerMetadata:
              RoomArProductManifest.byProductId[object.firestoreProductId],
        )..start(),
        child: const MarkerArView(),
      ),
    );

    testWidgets('no product selector and no developer controls', (
      tester,
    ) async {
      await setViewport(tester, const Size(393, 851));
      await tester.pumpWidget(customerHarness(MarkerArObject.chair));
      await tester.pumpAndSettle();

      // the four-product selector is gone…
      for (final o in MarkerArObject.values) {
        expect(
          find.byKey(ValueKey('marker-ar-object-${o.name}')),
          findsNothing,
        );
      }
      // …replaced by a read-only product label
      expect(find.text('Luna Accent Chair'), findsOneWidget);
      // no debug metrics toggle, no R10 Storage panel button
      expect(find.byIcon(Icons.bug_report_outlined), findsNothing);
      expect(find.byIcon(Icons.bug_report), findsNothing);
      expect(find.byIcon(Icons.cloud_download_outlined), findsNothing);
      // interaction chrome preserved
      expect(find.text('Face me'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.byIcon(Icons.straighten), findsOneWidget); // calibration
      expect(find.byIcon(Icons.print_outlined), findsOneWidget); // marker sheet
      expect(tester.takeException(), isNull);
    });

    testWidgets('the close button pops the route', (tester) async {
      await setViewport(tester, const Size(393, 851));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider(
                      create: (_) => MarkerArViewModel(
                        channel: channel,
                        mode: MarkerArLaunchMode.customerProduct,
                        initialObject: MarkerArObject.lamp,
                        customerMetadata: RoomArProductManifest
                            .byProductId['modern-table-lamp'],
                      )..start(),
                      child: const MarkerArView(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(AndroidView), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(AndroidView), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an engine-unavailable device offers an honest 3D-preview '
        'fallback', (tester) async {
      final badChannel = FakeRoomArMarkerChannel(
        config: MarkerArConfig.fromMap(const {'openCvOk': false}),
      );
      addTearDown(badChannel.close);
      await setViewport(tester, const Size(393, 851));
      String? routedTo;
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (s) {
            routedTo = s.name;
            return MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('PREVIEW STUB')),
            );
          },
          home: ChangeNotifierProvider(
            create: (_) => MarkerArViewModel(
              channel: badChannel,
              mode: MarkerArLaunchMode.customerProduct,
              initialObject: MarkerArObject.chair,
              customerMetadata:
                  RoomArProductManifest.byProductId['luna-accent-chair'],
            )..start(),
            child: const MarkerArView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Camera AR isn\'t available on this device'),
        findsOneWidget,
      );
      expect(find.text('View 3D preview'), findsOneWidget);
      expect(find.byType(AndroidView), findsNothing);

      await tester.tap(find.text('View 3D preview'));
      await tester.pumpAndSettle();
      expect(routedTo, RouteNames.roomArPreview);
      expect(find.text('PREVIEW STUB'), findsOneWidget);
    });

    testWidgets('camera denied → the permission screen offers a 3D preview', (
      tester,
    ) async {
      _PermissionMock.status = 0; // denied
      await setViewport(tester, const Size(393, 851));
      String? routedTo;
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (s) {
            routedTo = s.name;
            return MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('PREVIEW STUB')),
            );
          },
          home: ChangeNotifierProvider(
            create: (_) => MarkerArViewModel(
              channel: channel,
              mode: MarkerArLaunchMode.customerProduct,
              initialObject: MarkerArObject.sofa,
              customerMetadata:
                  RoomArProductManifest.byProductId['luna-3-seater-sofa'],
            )..start(),
            child: const MarkerArView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Camera access needed'), findsOneWidget);
      final link = find.text('View a 3D preview instead');
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(routedTo, RouteNames.roomArPreview);
    });
  });
}
