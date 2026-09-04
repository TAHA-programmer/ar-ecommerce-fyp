import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/routes/app_router.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_object.dart';
import 'package:twin_ar/features/room_ar/marker_ar/room_ar_session_args.dart';
import 'package:twin_ar/features/room_ar/room_ar_product_manifest.dart';

void main() {
  Future<void> pumpRoute(WidgetTester tester, RouteSettings settings) async {
    final route = AppRouter.onGenerateRoute(settings);
    await tester.pumpWidget(
      MaterialApp(home: Navigator(onGenerateRoute: (_) => route)),
    );
    await tester.pump();
  }

  testWidgets(
    'roomArSession without RoomArSessionArgs falls to an honest error route',
    (tester) async {
      await pumpRoute(
        tester,
        const RouteSettings(name: RouteNames.roomArSession),
      );
      expect(
        find.textContaining('Room AR is not available for this product'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'roomArSession with a String (wrong argument type) is also rejected',
    (tester) async {
      await pumpRoute(
        tester,
        const RouteSettings(
          name: RouteNames.roomArSession,
          arguments: 'luna-accent-chair',
        ),
      );
      expect(
        find.textContaining('Room AR is not available for this product'),
        findsOneWidget,
      );
    },
  );

  test('roomArSession with valid args returns a route for that product', () {
    final args = RoomArSessionArgs(
      object: MarkerArObject.chair,
      metadata: RoomArProductManifest.byProductId['luna-accent-chair']!,
      productTitle: 'Luna Accent Chair',
    );
    final route = AppRouter.onGenerateRoute(
      RouteSettings(name: RouteNames.roomArSession, arguments: args),
    );
    expect(route, isA<MaterialPageRoute<dynamic>>());
    expect(route.settings.name, RouteNames.roomArSession);
    expect(route.settings.arguments, same(args));
  });

  testWidgets('roomArPreview without RoomArSessionArgs → honest error route', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      const RouteSettings(name: RouteNames.roomArPreview),
    );
    expect(
      find.textContaining('3D preview is not available for this product'),
      findsOneWidget,
    );
  });

  testWidgets('roomArPreview with a String is also rejected', (tester) async {
    await pumpRoute(
      tester,
      const RouteSettings(
        name: RouteNames.roomArPreview,
        arguments: 'glass-coffee-table',
      ),
    );
    expect(
      find.textContaining('3D preview is not available for this product'),
      findsOneWidget,
    );
  });

  test('roomArPreview with valid args returns a route for that product', () {
    final args = RoomArSessionArgs(
      object: MarkerArObject.sofa,
      metadata: RoomArProductManifest.byProductId['luna-3-seater-sofa']!,
      productTitle: 'Luna Right-Chaise Sectional Sofa',
    );
    final route = AppRouter.onGenerateRoute(
      RouteSettings(name: RouteNames.roomArPreview, arguments: args),
    );
    expect(route, isA<MaterialPageRoute<dynamic>>());
    expect(route.settings.name, RouteNames.roomArPreview);
    expect(route.settings.arguments, same(args));
  });
}
