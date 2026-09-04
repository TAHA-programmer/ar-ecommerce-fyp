import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/customer_address_state.dart';
import 'package:twin_ar/core/data/address_repository.dart';
import 'package:twin_ar/core/data/mock_address_repository.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/address/views/address_form_view.dart';

/// An [AddressRepository] whose [addAddress] never resolves until
/// [completePendingAdd] is called - lets a test tap "Save" twice while the
/// first write is still in flight, to prove the double-submit guard.
class _SlowAddressRepository extends AddressRepository {
  final List<AddressModel> _addresses = [];
  Completer<AddressModel>? _pendingAdd;
  int addAddressCallCount = 0;

  @override
  int get generation => 0;
  @override
  bool get isLoading => false;
  @override
  bool get hasError => false;
  @override
  List<AddressModel> get addresses => List.unmodifiable(_addresses);

  @override
  Future<AddressModel> addAddress(
    AddressDraft draft, {
    bool makeDefault = false,
  }) {
    addAddressCallCount++;
    final completer = Completer<AddressModel>();
    _pendingAdd = completer;
    return completer.future;
  }

  void completePendingAdd() {
    final model = AddressModel(
      id: 'created-1',
      fullName: 'Jane Doe',
      phoneNumber: '03001234567',
      addressLine1: '123 Main St',
      city: 'Lahore',
      provinceOrState: 'Punjab',
      postalCode: '54000',
      isDefault: true,
      createdAt: DateTime.now(),
    );
    _addresses.add(model);
    _pendingAdd?.complete(model);
  }

  @override
  Future<void> updateAddress(
    AddressModel address, {
    bool makeDefault = false,
  }) async {}
  @override
  Future<void> setDefaultAddress(String addressId) async {}
  @override
  Future<void> deleteAddress(String addressId) async {}
}

void main() {
  Widget createTestWidget(CustomerAddressState state) {
    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: state)],
      child: const MaterialApp(home: AddressFormView()),
    );
  }

  group('AddressFormView', () {
    late MockAddressRepository repository;
    late CustomerAddressState addressState;

    setUp(() {
      repository = MockAddressRepository();
      addressState = CustomerAddressState(repository);
    });

    testWidgets(
      'submitting with a required field left blank does NOT navigate back - '
      'regression test for the bug where AddressFormViewModel.save() '
      'returned null (the same value as success) on a failed Form.validate(), '
      'and the view treated that null as "pop the screen"',
      (tester) async {
        await tester.pumpWidget(createTestWidget(addressState));
        await tester.pumpAndSettle();

        // Every required field is left blank - Full Name, Phone, Address
        // Line 1, City, Province, Postal Code all have a non-null validator
        // that fails on empty input.
        expect(find.text('Add New Address'), findsOneWidget);

        await tester.ensureVisible(find.text('Save Address'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Address'));
        await tester.pumpAndSettle();

        // Still on the form - never popped back to (nonexistent) previous
        // route, and no address was created.
        expect(find.text('Add New Address'), findsOneWidget);
        expect(find.text('Required'), findsWidgets);
        expect(repository.addresses, isEmpty);
      },
    );

    testWidgets('submitting a fully valid form DOES navigate back and '
        'creates the address', (tester) async {
      await tester.pumpWidget(createTestWidget(addressState));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter your full name'),
        'Jane Doe',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter your phone number'),
        '03001234567',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'House, Street, etc.'),
        '123 Main St',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'City'),
        'Lahore',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Province'),
        'Punjab',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Postal Code'),
        '54000',
      );

      await tester.ensureVisible(find.text('Save Address'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Address'));
      await tester.pumpAndSettle();

      // The form screen is gone (popped) and the address was created.
      expect(find.text('Add New Address'), findsNothing);
      expect(repository.addresses, hasLength(1));
      expect(repository.addresses.single.fullName, 'Jane Doe');
    });

    testWidgets(
      'tapping Save twice while the first save is still in flight issues '
      'only ONE repository write and does not navigate until it resolves',
      (tester) async {
        final slowRepository = _SlowAddressRepository();
        final slowState = CustomerAddressState(slowRepository);

        await tester.pumpWidget(createTestWidget(slowState));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Enter your full name'),
          'Jane Doe',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Enter your phone number'),
          '03001234567',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'House, Street, etc.'),
          '123 Main St',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'City'),
          'Lahore',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Province'),
          'Punjab',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Postal Code'),
          '54000',
        );

        await tester.ensureVisible(find.text('Save Address'));
        await tester.pumpAndSettle();

        // First tap starts the (still-pending) save.
        await tester.tap(find.text('Save Address'));
        await tester.pump();

        // Second tap while it's still in flight - the button is disabled
        // (isSaving), but tap anyway to prove the ViewModel-level guard
        // holds even if a stray event slipped through.
        await tester.tap(find.text('Save Address'), warnIfMissed: false);
        await tester.pump();

        expect(
          slowRepository.addAddressCallCount,
          1,
          reason: 'a duplicate submit must not issue a second write',
        );
        expect(find.text('Add New Address'), findsOneWidget);

        // Let the first (only) save resolve.
        slowRepository.completePendingAdd();
        await tester.pumpAndSettle();

        expect(find.text('Add New Address'), findsNothing);
        expect(slowRepository.addresses, hasLength(1));
      },
    );
  });
}
