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
}
