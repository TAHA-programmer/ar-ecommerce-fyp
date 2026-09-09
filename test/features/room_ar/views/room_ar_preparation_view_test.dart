import 'package:flutter/material.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/features/room_ar/capability/room_ar_capability.dart';
import 'package:twin_ar/features/room_ar/marker_ar/room_ar_session_args.dart';
import 'package:twin_ar/features/room_ar/viewmodels/room_ar_preparation_viewmodel.dart';
import 'package:twin_ar/features/room_ar/views/room_ar_preparation_view.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';

import '../capability/fake_capability_service.dart';

void main() {
  late MockProductDetailsRepository repository;

  setUp(() {
    repository = MockProductDetailsRepository(
      MockCommerceDatabase(),
      simulateDelay: false,
    );
  });

  Object? lastRouteArgs;
  String? lastRouteName;

  Widget harness(
    String productId, {
    RoomArDeviceCapabilities caps = FakeRoomArCapabilityService.infinix,
  }) {
    lastRouteArgs = null;
    lastRouteName = null;
    return MaterialApp(
      onGenerateRoute: (settings) {
        lastRouteName = settings.name;
        lastRouteArgs = settings.arguments;
        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('STUB')),
        );
      },
      home: ChangeNotifierProvider(
        create: (context) => RoomArPreparationViewModel(
          repository: repository,
          capabilityService: FakeRoomArCapabilityService(caps),
          productId: productId,
        ),
        child: RoomArPreparationView(productId: productId),
      ),
    );
  }

  group('RoomArPreparationView — tier-adaptive', () {
    testWidgets('Tier 1 (ARCore) device: markerless copy + "Start AR" → '
        'roomArCoreSession (Phase 9.2 R6)', (tester) async {
      await tester.pumpWidget(
        harness(
          'luna-accent-chair',
          caps: FakeRoomArCapabilityService.arCoreDevice,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Luna Accent Chair'), findsOneWidget);
      expect(find.text('Start AR'), findsOneWidget);
      expect(find.textContaining('no marker to print'), findsOneWidget);
      // no Tier-2 print instructions on the Tier-1 screen
      expect(find.textContaining('Print the'), findsNothing);

      await tester.ensureVisible(find.text('Start AR'));
      await tester.tap(find.text('Start AR'));
      await tester.pumpAndSettle();
      expect(lastRouteName, RouteNames.roomArCoreSession);
      expect(
        (lastRouteArgs as RoomArSessionArgs).firestoreProductId,
        'luna-accent-chair',
      );
    });

    testWidgets('Tier 2 device: marker copy + "Start AR" → roomArSession', (
      tester,
    ) async {
      await tester.pumpWidget(harness('luna-accent-chair'));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Luna Accent Chair'), findsOneWidget);
      expect(find.text('Start AR'), findsOneWidget);
      expect(find.textContaining('printed marker'), findsWidgets);
      expect(find.textContaining('Print the'), findsOneWidget);

      await tester.ensureVisible(find.text('Start AR'));
      await tester.tap(find.text('Start AR'));
      await tester.pumpAndSettle();
      expect(lastRouteName, RouteNames.roomArSession);
      expect(
        (lastRouteArgs as RoomArSessionArgs).firestoreProductId,
        'luna-accent-chair',
      );
      expect(find.text('Coming soon'), findsNothing);
    });

    testWidgets(
      'Tier 3 device: preview copy + "View 3D Preview" → roomArPreview',
      (tester) async {
        await tester.pumpWidget(
          harness(
            'glass-coffee-table',
            caps: FakeRoomArCapabilityService.noCameraAr,
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(find.text('Start AR'), findsNothing);
        expect(find.text('View 3D Preview'), findsOneWidget);
        expect(find.textContaining('interactive 3D preview'), findsWidgets);
        // no marker instructions on the Tier-3 screen
        expect(find.textContaining('Print the'), findsNothing);

        await tester.ensureVisible(find.text('View 3D Preview'));
        await tester.tap(find.text('View 3D Preview'));
        await tester.pumpAndSettle();
        expect(lastRouteName, RouteNames.roomArPreview);
        expect(lastRouteArgs, isA<RoomArSessionArgs>());
      },
    );

    testWidgets('Tier 2 screen also offers a no-printer 3D preview link', (
      tester,
    ) async {
      await tester.pumpWidget(harness('modern-table-lamp'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final link = find.text('No printer? View a 3D preview instead');
      expect(link, findsOneWidget);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(lastRouteName, RouteNames.roomArPreview);
    });

    testWidgets('unsupported device: no launch button, honest message', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness('luna-3-seater-sofa', caps: FakeRoomArCapabilityService.noGles),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Start AR'), findsNothing);
      expect(find.text('View 3D Preview'), findsNothing);
      expect(
        find.textContaining('can\'t run the 3D experience'),
        findsOneWidget,
      );
      expect(find.text('Go Back'), findsOneWidget);
    });

    testWidgets('roomAr product with no approved model: no launch at all', (
      tester,
    ) async {
      await tester.pumpWidget(harness('other-product-3'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Start AR'), findsNothing);
      expect(find.text('View 3D Preview'), findsNothing);
      expect(find.textContaining('isn\'t ready yet'), findsOneWidget);
      expect(find.text('Go Back'), findsOneWidget);
    });

    testWidgets('non-roomAr product shows the existing error', (tester) async {
      await tester.pumpWidget(harness('mens-oxford-shirt'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(
        find.text('This product does not support Room AR.'),
        findsOneWidget,
      );
    });
  });
}
