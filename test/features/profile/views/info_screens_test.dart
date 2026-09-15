import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/core/constants/app_contact.dart';
import 'package:twin_ar/core/services/mail_launcher_service.dart';
import 'package:twin_ar/core/services/mock_mail_launcher_service.dart';
import 'package:twin_ar/features/profile/views/help_support_view.dart';
import 'package:twin_ar/features/profile/views/room_ar_info_view.dart';
import 'package:twin_ar/features/profile/views/virtual_try_on_info_view.dart';
import 'package:twin_ar/features/profile/views/about_twin_ar_view.dart';

void main() {
  Widget wrapHelpSupport(MailLauncherService service) {
    return MaterialApp(
      home: Provider<MailLauncherService>.value(
        value: service,
        child: const HelpSupportView(),
      ),
    );
  }

  testWidgets('HelpSupportView renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(wrapHelpSupport(MockMailLauncherService()));
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('How can we help?'), findsOneWidget);
    expect(find.text('Contact Support'), findsWidgets);
    expect(find.text(AppContact.supportEmail), findsOneWidget);
  });

  test('AppContact.supportEmail is the verified real mailbox, not the old '
      'placeholder', () {
    expect(AppContact.supportEmail, 'twinar.support@gmail.com');
  });

  testWidgets(
    'HelpSupportView Contact Support launches the mail app on success',
    (WidgetTester tester) async {
      final service = MockMailLauncherService(result: true);
      await tester.pumpWidget(wrapHelpSupport(service));

      final button = find.widgetWithText(ElevatedButton, 'Contact Support');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(service.callCount, 1);
      expect(find.text('Opening your email app...'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4)); // drain AppToast timer
    },
  );

  testWidgets(
    'HelpSupportView Contact Support shows a fallback message when no '
    'email app is available',
    (WidgetTester tester) async {
      final service = MockMailLauncherService(result: false);
      await tester.pumpWidget(wrapHelpSupport(service));

      final button = find.widgetWithText(ElevatedButton, 'Contact Support');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(service.callCount, 1);
      expect(find.textContaining("Couldn't open an email app"), findsOneWidget);
      expect(find.textContaining(AppContact.supportEmail), findsWidgets);

      await tester.pump(const Duration(seconds: 4)); // drain AppToast timer
    },
  );

  testWidgets('RoomArInfoView renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: RoomArInfoView()));
    expect(find.text('How Room AR Works'), findsOneWidget);
    expect(find.text('Choose an AR-enabled product'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('VirtualTryOnInfoView renders correctly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: VirtualTryOnInfoView()));
    expect(find.text('How Virtual Try-On Works'), findsOneWidget);
    expect(find.text('Choose a supported clothing item'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('AboutTwinArView renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutTwinArView()));
    expect(find.text('About TWin AR'), findsWidgets);
    expect(find.text('What TWin AR Offers'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
  });
}
