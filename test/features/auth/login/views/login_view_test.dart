import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/features/auth/login/views/login_view.dart';
import 'package:twin_ar/features/auth/login/viewmodels/login_viewmodel.dart';
import 'package:twin_ar/features/auth/repositories/auth_repository.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/features/auth/widgets/social_login_button.dart';
import 'package:twin_ar/features/auth/widgets/auth_footer_link.dart';
import 'package:twin_ar/core/widgets/fields/app_text_field.dart';
import 'package:twin_ar/core/widgets/fields/app_password_field.dart';
import 'package:twin_ar/core/widgets/buttons/app_primary_button.dart';
import 'package:twin_ar/app/routes/route_names.dart';

void main() {
  Widget createTestWidget({
    String? navigatedRoute,
    Function(String)? onNavigate,
  }) {
    SharedPreferences.setMockInitialValues({});
    return MaterialApp(
      routes: {
        RouteNames.home: (context) {
          if (onNavigate != null) onNavigate(RouteNames.home);
          return const Scaffold(body: Text('HomeView'));
        },
        RouteNames.adminDashboard: (context) {
          if (onNavigate != null) onNavigate(RouteNames.adminDashboard);
          return const Scaffold(body: Text('AdminDashboard'));
        },
      },
      builder: (context, child) {
        return MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: child!,
        );
      },
      home: MultiProvider(
        providers: [
          Provider<AuthRepository>(create: (_) => MockAuthRepository()),
          ChangeNotifierProvider(create: (_) => AuthSessionState()),
          ChangeNotifierProvider(
            create: (context) => LoginViewModel(
              context.read<AuthRepository>(),
              context.read<AuthSessionState>(),
            ),
          ),
        ],
        child: const LoginView(),
      ),
    );
  }

  testWidgets(
    'LoginView renders without overflow on small screen and has required elements',
    (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(AppTextField), findsNWidgets(2));
      expect(find.byType(AppPasswordField), findsOneWidget);
      expect(find.text('Remember Me'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.byType(AppPrimaryButton), findsOneWidget);
      expect(find.byType(SocialLoginButton), findsOneWidget);
      expect(find.byType(AuthFooterLink), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Valid customer credentials navigate to Home', (
    WidgetTester tester,
  ) async {
    String? pushedRoute;
    await tester.pumpWidget(
      createTestWidget(onNavigate: (route) => pushedRoute = route),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.emailAddress,
      ),
      'customer@twinar.com',
    );
    await tester.enterText(find.byType(TextField).last, 'Customer123');

    final buttonFinder = find.byType(AppPrimaryButton);
    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle(
      const Duration(seconds: 1),
    ); // wait for mock network delay

    expect(pushedRoute, equals(RouteNames.home));
  });

  testWidgets('Valid admin credentials navigate to Admin Dashboard', (
    WidgetTester tester,
  ) async {
    String? pushedRoute;
    await tester.pumpWidget(
      createTestWidget(onNavigate: (route) => pushedRoute = route),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.emailAddress,
      ),
      'admin@twinar.com',
    );
    await tester.enterText(find.byType(TextField).last, 'Admin123');

    final buttonFinder = find.byType(AppPrimaryButton);
    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(pushedRoute, equals(RouteNames.adminDashboard));
  });
}
