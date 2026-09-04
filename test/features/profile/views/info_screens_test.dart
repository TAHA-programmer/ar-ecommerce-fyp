import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/profile/views/help_support_view.dart';
import 'package:twin_ar/features/profile/views/room_ar_info_view.dart';
import 'package:twin_ar/features/profile/views/virtual_try_on_info_view.dart';
import 'package:twin_ar/features/profile/views/about_twin_ar_view.dart';

void main() {
  testWidgets('HelpSupportView renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpSupportView()));
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('How can we help?'), findsOneWidget);
    expect(find.text('Contact Support'), findsWidgets);
  });

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
