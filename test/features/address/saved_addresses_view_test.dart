import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/app_router.dart';
import 'package:twin_ar/app/viewmodels/customer_address_state.dart';
import 'package:twin_ar/core/data/mock_address_repository.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/address/views/saved_addresses_view.dart';
import 'package:twin_ar/features/address/widgets/address_card.dart';
import 'package:twin_ar/features/address/widgets/address_empty_state.dart';

AddressDraft _draft({required String suffix}) {
  return AddressDraft(
    fullName: 'Test User $suffix',
    phoneNumber: '123',
    addressLine1: 'Line $suffix',
    city: 'City',
    provinceOrState: 'State',
    postalCode: '0000$suffix',
  );
}

void main() {
  Widget createTestWidget(CustomerAddressState state) {
    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: state)],
      child: MaterialApp(
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: const SavedAddressesView(),
      ),
    );
  }

  group('SavedAddressesView', () {
    late MockAddressRepository repository;
    late CustomerAddressState addressState;

    setUp(() {
      repository = MockAddressRepository();
      addressState = CustomerAddressState(repository);
    });

    testWidgets('renders empty state correctly with custom text', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget(addressState));
      await tester.pumpAndSettle();

      expect(find.byType(AddressEmptyState), findsOneWidget);
      expect(find.text('No saved addresses yet'), findsOneWidget);
      expect(
        find.text('Add an address to make checkout faster.'),
        findsOneWidget,
      );
    });

    testWidgets('renders multiple addresses without checkout UI', (
      tester,
    ) async {
      await repository.addAddress(_draft(suffix: '1'));
      await repository.addAddress(_draft(suffix: '2'));

      await tester.pumpWidget(createTestWidget(addressState));
      await tester.pumpAndSettle();

      expect(find.byType(AddressCard), findsNWidgets(2));
      // No Proceed to Checkout button should exist
      expect(find.text('Proceed to Checkout'), findsNothing);
    });

    testWidgets('Set as Default updates CustomerAddressState', (tester) async {
      await repository.addAddress(_draft(suffix: '1'));
      await repository.addAddress(_draft(suffix: '2'));

      await tester.pumpWidget(createTestWidget(addressState));
      await tester.pumpAndSettle();

      // Find the second address's Set as default button (since it's not default)
      final setAsDefaultButton = find.text('Set as default');
      expect(setAsDefaultButton, findsOneWidget);

      await tester.tap(setAsDefaultButton);
      await tester.pumpAndSettle();

      expect(addressState.addresses[1].isDefault, isTrue);
      expect(addressState.addresses[0].isDefault, isFalse);
    });

    testWidgets('Delete confirmation appears and cancels correctly', (
      tester,
    ) async {
      await repository.addAddress(_draft(suffix: '1'));

      await tester.pumpWidget(createTestWidget(addressState));
      await tester.pumpAndSettle();

      final deleteIcon = find.byIcon(Icons.delete_outline);
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      expect(find.text('Delete Address?'), findsOneWidget);

      final cancelButton = find.text('Cancel');
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();

      expect(find.text('Delete Address?'), findsNothing);
      expect(addressState.addresses.length, 1);
    });

    testWidgets('Delete confirmation removes address on confirm', (
      tester,
    ) async {
      await repository.addAddress(_draft(suffix: '1'));

      await tester.pumpWidget(createTestWidget(addressState));
      await tester.pumpAndSettle();

      final deleteIcon = find.byIcon(Icons.delete_outline);
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      final deleteButton = find.widgetWithText(ElevatedButton, 'Delete');
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(addressState.addresses.isEmpty, isTrue);
    });
  });
}
