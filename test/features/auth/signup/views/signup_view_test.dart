import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/features/auth/signup/viewmodels/signup_viewmodel.dart';
import 'package:twin_ar/features/auth/signup/views/signup_view.dart';
import 'package:twin_ar/core/widgets/fields/app_text_field.dart';
import 'package:twin_ar/core/widgets/fields/app_password_field.dart';
import 'package:twin_ar/core/widgets/buttons/app_primary_button.dart';
import 'package:twin_ar/core/widgets/fields/app_checkbox.dart';

void main() {
  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => SignupViewModel(MockAuthRepository()),
        child: const SignupView(),
      ),
    );
  }

  testWidgets(
    'SignupView renders without overflow on small screen and has required elements',
    (WidgetTester tester) async {
      // Set a small viewport to test responsiveness/overflow
      tester.view.physicalSize = const Size(
        1080,
        1920,
      ); // roughly standard phone
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byType(AppTextField),
        findsNWidgets(5),
      ); // Name, Email, Phone, Password, Confirm (Password uses AppTextField internally)
      expect(
        find.byType(AppPasswordField),
        findsNWidgets(2),
      ); // Password, Confirm

      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Phone No'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);

      expect(find.byType(AppCheckbox), findsOneWidget);

      // Check for RichText elements by looking for the widget type and some text content
      final richTexts = find.byType(RichText);
      expect(richTexts, findsWidgets);

      expect(find.byType(AppPrimaryButton), findsOneWidget);

      // Reset view
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
