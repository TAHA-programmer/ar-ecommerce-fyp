import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/onboarding/views/onboarding_view.dart';
import 'package:twin_ar/features/onboarding/viewmodels/onboarding_viewmodel.dart';

void main() {
  testWidgets('Onboarding screens do not overflow on a small device', (
    WidgetTester tester,
  ) async {
    // Set a realistic small Android logical viewport (e.g., 360x640)
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;

    // Build the widget
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => OnboardingViewModel()),
        ],
        child: MaterialApp(
          home: const OnboardingView(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('Login Route')),
          },
        ),
      ),
    );

    // If there is a RenderFlex overflow, it will be thrown during pump
    // We use pump instead of pumpAndSettle because Page 3 has an infinite CircularProgressIndicator.
    await tester.pump(const Duration(seconds: 1));

    // Navigate to Page 2
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump(const Duration(seconds: 1));

    // Navigate to Page 3
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump(const Duration(seconds: 1));

    // Clean up
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
