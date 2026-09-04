import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/customer_address_state.dart';
import 'package:twin_ar/core/data/address_repository.dart';
import 'package:twin_ar/core/data/mock_address_repository.dart';
import 'package:twin_ar/features/address/models/address_model.dart';

AddressDraft _draft({String fullName = 'Test User'}) => AddressDraft(
  fullName: fullName,
  phoneNumber: '1',
  addressLine1: 'L1',
  city: 'C',
  provinceOrState: 'P',
  postalCode: '0',
);

/// Test-only [AddressRepository] double that lets a test control EXACTLY
/// when [addAddress] resolves relative to an identity ([generation])
/// change - used to deterministically prove
/// `CustomerAddressState.addAddress`'s generation guard (a mid-write
/// account switch must never apply the created address to the new
/// account's selection state), without depending on real Firestore/network
/// timing.
class _FakeSlowAddressRepository extends AddressRepository {
  int _generation = 0;
  Completer<AddressModel>? _pendingAdd;

  @override
  int get generation => _generation;

  @override
  bool get isLoading => false;

  @override
  bool get hasError => false;

  @override
  List<AddressModel> get addresses => const [];

  /// Simulates the active identity changing (e.g. a signed-in account
  /// switch) WHILE a call to [addAddress] is still in flight.
  void simulateIdentityChange() {
    _generation++;
    notifyListeners();
  }

  @override
  Future<AddressModel> addAddress(
    AddressDraft draft, {
    bool makeDefault = false,
  }) {
    final completer = Completer<AddressModel>();
    _pendingAdd = completer;
    return completer.future;
  }

  /// Resolves the pending [addAddress] call - call this AFTER optionally
  /// calling [simulateIdentityChange], to control the exact ordering.
  void completePendingAdd(AddressModel model) {
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
  group('CustomerAddressState', () {
    test('addAddress selects the newly-created address using the real '
        'repository-allocated id', () async {
      final repository = MockAddressRepository();
      final state = CustomerAddressState(repository);

      final error = await state.addAddress(_draft());

      expect(error, isNull);
      expect(state.selectedAddressId, isNotNull);
      expect(state.selectedAddress?.fullName, 'Test User');
      expect(state.selectedAddressId, state.addresses.single.id);
    });

    test('addAddress(makeDefault: true) immediately promotes a LATER '
        'address to default, atomically with its creation - never a '
        'separate follow-up call', () async {
      final repository = MockAddressRepository();
      final state = CustomerAddressState(repository);

      await state.addAddress(_draft(fullName: 'First'));
      final error = await state.addAddress(
        _draft(fullName: 'Second'),
        makeDefault: true,
      );

      expect(error, isNull);
      final second = state.addresses.firstWhere((a) => a.fullName == 'Second');
      final first = state.addresses.firstWhere((a) => a.fullName == 'First');
      expect(second.isDefault, isTrue);
      expect(first.isDefault, isFalse);
      // The previously-default address is never left ambiguously
      // default too - exactly one address is default.
      expect(state.addresses.where((a) => a.isDefault).length, 1);
    });

    test('a mid-write account switch cannot apply the created address to '
        'the new account\'s selection state - the generation guard, not '
        'listener/cache timing, gates the optimistic update', () async {
      final repository = _FakeSlowAddressRepository();
      final state = CustomerAddressState(repository);
      expect(state.selectedAddressId, isNull);

      final future = state.addAddress(_draft());

      // The account switches WHILE the write above is still in flight.
      repository.simulateIdentityChange();
      repository.completePendingAdd(
        AddressModel(
          id: 'stale-address-for-old-account',
          fullName: 'Old Account Address',
          phoneNumber: '1',
          addressLine1: 'L1',
          city: 'C',
          provinceOrState: 'P',
          postalCode: '0',
          isDefault: true,
          createdAt: DateTime.now(),
        ),
      );

      final error = await future;

      // The write itself is reported as having succeeded (it really did,
      // for the OLD account) - but the new account's local state must
      // never be pointed at that address.
      expect(error, isNull);
      expect(state.selectedAddressId, isNot('stale-address-for-old-account'));
      expect(state.selectedAddressId, isNull);
    });

    test('selection falls back default -> first -> null when the selected '
        'address disappears', () async {
      final repository = MockAddressRepository();
      final state = CustomerAddressState(repository);

      // "First" becomes the default automatically (first address ever
      // created); "Second" is not the default.
      await state.addAddress(_draft(fullName: 'First'));
      await state.addAddress(_draft(fullName: 'Second'));
      final secondId = state.addresses
          .firstWhere((a) => a.fullName == 'Second')
          .id;
      // Explicitly select the NON-default address to make the fallback
      // path meaningful.
      state.selectAddress(secondId);
      expect(state.selectedAddressId, secondId);

      // Delete the selected (non-default) address - falls back to default.
      await state.deleteAddress(secondId);
      expect(state.selectedAddressId, isNot(secondId));
      expect(state.selectedAddress?.fullName, 'First');

      // Delete the last remaining address - falls back to null.
      final lastId = state.addresses.single.id;
      await state.deleteAddress(lastId);
      expect(state.selectedAddressId, isNull);
      expect(state.selectedAddress, isNull);
    });

    test('signed-out-style repository failure returns a clean error and '
        'does not create local shared state', () async {
      final repository = MockAddressRepository()
        ..failAddAddressWith = StateError('You are not signed in.');
      final state = CustomerAddressState(repository);

      final error = await state.addAddress(_draft());

      expect(error, 'You are not signed in.');
      expect(state.addresses, isEmpty);
      expect(state.selectedAddressId, isNull);
    });

    test('defaultAddress passes through from the repository', () async {
      final repository = MockAddressRepository();
      final state = CustomerAddressState(repository);
      await state.addAddress(_draft());
      expect(state.defaultAddress, isNotNull);
      expect(state.defaultAddress!.isDefault, isTrue);
    });
  });
}
