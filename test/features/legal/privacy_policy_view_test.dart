import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/legal/privacy/views/privacy_policy_view.dart';
import 'package:twin_ar/features/legal/widgets/legal_section_card.dart';

void main() {
  testWidgets(
    'PrivacyPolicyView renders without overflow on small screen and has required elements',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyView()));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy'), findsWidgets);
      expect(find.textContaining('Learn how TWin AR collects'), findsOneWidget);
      expect(find.byType(LegalSectionCard), findsWidgets);

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );

  testWidgets(
    'Phase 9.3 Stage 5 fix — Room AR and Virtual Try-On camera/photo use are '
    'described accurately and separately, never conflated',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyView()));
      await tester.pumpAndSettle();

      // Room AR genuinely never leaves the device — this claim must stay.
      expect(find.textContaining('Room AR'), findsWidgets);
      expect(
        find.textContaining(
          'processed locally on your device and is not permanently stored '
          'or transmitted',
        ),
        findsOneWidget,
      );

      // Virtual Try-On genuinely uploads a still photo to a third party and
      // must say so — the old copy falsely claimed this was also "local"
      // and "not transmitted".
      expect(find.text('Virtual Try-On Photos'), findsOneWidget);
      expect(find.textContaining('Google Gemini'), findsWidgets);
      expect(find.textContaining('securely uploaded and sent'), findsOneWidget);
      expect(
        find.textContaining(
          'deleted immediately after the preview is generated',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('within 24 hours'), findsOneWidget);
      expect(find.textContaining('Delete My Try-On Data'), findsOneWidget);

      // No single sentence describes AR and VTO as one video feed that is
      // both local and not transmitted (the exact bug: room AR + VTO
      // conflated under one "processed locally... not transmitted" claim).
      expect(
        find.textContaining(
          'room AR and virtual try-on features, TWin AR requires temporary '
          'access',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'FCM Stage S6 - Push Notifications section is accurate: opt-in, what is stored, '
    'what is sent, controls, removal, retention, no delivery guarantee',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyView()));
      await tester.pumpAndSettle();

      expect(find.text('Push Notifications'), findsOneWidget);
      expect(find.text('Last updated: October 2026'), findsOneWidget);
      // optional + contextual, never at first open
      expect(
        find.textContaining('Push notifications are optional'),
        findsOneWidget,
      );
      expect(
        find.textContaining('never when you first open the app'),
        findsOneWidget,
      );
      // what is stored
      expect(find.textContaining('device notification token'), findsOneWidget);
      expect(find.textContaining('random installation ID'), findsOneWidget);
      // what is sent / not sent
      expect(
        find.textContaining('confirmed, shipped, delivered or cancelled'),
        findsOneWidget,
      );
      expect(
        find.textContaining('never your address, items, or payment details'),
        findsOneWidget,
      );
      // controls and the D7 inbox guarantee
      expect(find.textContaining('turn each category off'), findsOneWidget);
      expect(
        find.textContaining('Notification Centre still records the update'),
        findsOneWidget,
      );
      // removal + retention
      expect(
        find.textContaining('we ask our servers to remove your device token'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Device tokens are also deleted if your account is deleted',
        ),
        findsOneWidget,
      );
      // best-effort server removal is described honestly (no absolute claim)
      expect(
        find.textContaining('leftover record is cleaned up automatically'),
        findsOneWidget,
      );
      expect(
        find.textContaining('token is removed when you log out'),
        findsNothing,
      );
      expect(find.textContaining('about 90 days'), findsOneWidget);
      // honest about delivery
      expect(
        find.textContaining('Push delivery is not guaranteed'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'FCM Stage S6 - Firebase Cloud Messaging is listed as a third-party service',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyView()));
      await tester.pumpAndSettle();
      expect(find.text('Third-Party Services'), findsOneWidget);
      expect(
        find.textContaining('Firebase Cloud Messaging for push notifications'),
        findsOneWidget,
      );
      // the pre-existing claims are preserved
      expect(find.textContaining('Stripe for payments'), findsOneWidget);
      expect(
        find.textContaining('Google Gemini for Virtual Try-On'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'FCM Stage S6 - the policy has exactly 15 sections after inserting Push Notifications',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyView()));
      await tester.pumpAndSettle();
      final cards = tester.widgetList<LegalSectionCard>(
        find.byType(LegalSectionCard),
      );
      expect(cards.length, 15);
    },
  );
}
