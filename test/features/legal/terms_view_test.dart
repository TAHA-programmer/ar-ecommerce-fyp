import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/legal/terms/views/terms_view.dart';
import 'package:twin_ar/features/legal/widgets/legal_section_card.dart';

void main() {
  testWidgets(
    'TermsView renders without overflow on small screen and has required elements',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(const MaterialApp(home: TermsView()));
      await tester.pumpAndSettle();

      expect(find.text('Terms & Conditions'), findsWidgets);
      expect(
        find.textContaining('Please read these terms carefully'),
        findsOneWidget,
      );
      expect(find.byType(LegalSectionCard), findsWidgets);

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
}
