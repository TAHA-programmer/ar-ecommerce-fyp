import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/features/auth/forgot_password/viewmodels/forgot_password_viewmodel.dart';
import 'package:twin_ar/features/auth/forgot_password/views/forgot_password_view.dart';
import 'package:twin_ar/core/widgets/fields/app_text_field.dart';
import 'package:twin_ar/core/widgets/buttons/app_primary_button.dart';
import 'package:twin_ar/features/auth/widgets/auth_header.dart';
import 'package:twin_ar/features/auth/widgets/auth_footer_link.dart';

void main() {
  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => ForgotPasswordViewModel(MockAuthRepository()),
        child: const ForgotPasswordView(),
      ),
    );
  }

  testWidgets(
    'ForgotPasswordView renders without overflow on small screen and has required elements',
    (WidgetTester tester) async {
      // Set a realistic small phone screen size (e.g., iPhone SE)
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Verify AuthHeader exists
      expect(find.byType(AuthHeader), findsOneWidget);

      // Verify Image exists (for illustration)
      expect(find.byType(Image), findsWidgets);

      // Verify Heading
      expect(find.text('Forgot Password', findRichText: true), findsOneWidget);

      // Verify Subtitle
      expect(find.textContaining('Enter your email'), findsWidgets);

      // Verify Text Field
      expect(find.byType(AppTextField), findsOneWidget);
      expect(find.text('Email'), findsWidgets);

      // Verify Button
      expect(find.byType(AppPrimaryButton), findsOneWidget);
      expect(find.text('Send Reset Link'), findsWidgets);

      // Verify Footer Link
      expect(find.byType(AuthFooterLink), findsOneWidget);
      expect(find.text('Back to Log In', findRichText: true), findsWidgets);

      // Reset view
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
}
