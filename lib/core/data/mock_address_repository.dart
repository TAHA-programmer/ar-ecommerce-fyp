import 'package:flutter/foundation.dart';

import '../../features/address/models/address_model.dart';
import 'address_repository.dart';

/// In-memory test double for [AddressRepository], mirroring
/// `MockCategoryRepository`/`MockCommerceDatabase`'s role in this codebase -
/// not used in production, gives ViewModel/widget tests a Firebase-free
/// seam. Deliberately has no uid/`AuthSessionState` concept of its own
/// (uid-switch/generation-guard behavior is `FirestoreAddressRepository`'s
/// concern, covered by its own tests) - a `MockAddressRepository` instance
/// simply represents "whatever address data the current test scenario
/// wants", matching `MockCategoryRepository`'s established convention.
/// [generation] is always `0` accordingly - a single continuous mock
/// session has no notion of an identity change.
class MockAddressRepository extends AddressRepository {
  final List<AddressModel> _addresses;
  String? _defaultId;
  bool _isLoading;
  bool _hasError = false;
  int _idCounter = 0;

  /// When set, the next `addAddress`/`updateAddress`/`setDefaultAddress`/
  /// `deleteAddress` call throws this instead of succeeding - mirrors
  /// `MockCategoryRepository`'s established failure-injection convention.
  Object? failAddAddressWith;
  Object? failUpdateAddressWith;
  Object? failSetDefaultAddressWith;
  Object? failDeleteAddressWith;

  MockAddressRepository({List<AddressModel>? initialAddresses})
    : _addresses = List.of(initialAddresses ?? const []),
      _isLoading = false {
    _defaultId = _addresses.isEmpty
        ? null
        : _addresses
              .firstWhere((a) => a.isDefault, orElse: () => _addresses.first)
              .id;
  }

  @override
  int get generation => 0;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get hasError => _hasError;

  @override
  List<AddressModel> get addresses {
    final sorted = List<AddressModel>.from(
      _addresses.map((a) => a.copyWith(isDefault: a.id == _defaultId)),
    );
    sorted.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return List.unmodifiable(sorted);
  }

  /// Test-only: simulates the initial-loading state.
  void simulateLoading() {
    _isLoading = true;
    notifyListeners();
  }

  /// Test-only: simulates a stream error (e.g. offline).
  void simulateError() {
    _isLoading = false;
    _hasError = true;
    notifyListeners();
  }

  /// Test-only: simulates recovery from a prior error/loading state with a
  /// fresh snapshot.
  void simulateRecovery(List<AddressModel> addresses) {
    _addresses
      ..clear()
      ..addAll(addresses);
    _defaultId = addresses.isEmpty
        ? null
        : addresses
              .firstWhere((a) => a.isDefault, orElse: () => addresses.first)
              .id;
    _isLoading = false;
    _hasError = false;
    notifyListeners();
  }

  @override
  Future<AddressModel> addAddress(
    AddressDraft draft, {
    bool makeDefault = false,
  }) async {
    if (failAddAddressWith != null) throw failAddAddressWith!;
    final index = _idCounter++;
    final id = 'mock-address-$index';
    final becomesDefault = makeDefault || _addresses.isEmpty;
    final model = AddressModel(
      id: id,
      label: draft.label,
      fullName: draft.fullName,
      phoneNumber: draft.phoneNumber,
      addressLine1: draft.addressLine1,
      addressLine2: draft.addressLine2,
      city: draft.city,
      provinceOrState: draft.provinceOrState,
      postalCode: draft.postalCode,
      isDefault: becomesDefault,
      // Offset by `index` (not a bare `DateTime.now()`) so a tight test
      // loop that creates several addresses back-to-back can never see two
      // ties for the same microsecond - `addresses`' deterministic
      // createdAt-ordering guarantee must hold even under a fast clock.
      createdAt: DateTime.now().add(Duration(microseconds: index)),
    );
    _addresses.add(model);
    if (becomesDefault) _defaultId = id;
    notifyListeners();
    return model.copyWith(isDefault: model.id == _defaultId);
  }

  @override
  Future<void> updateAddress(
    AddressModel address, {
    bool makeDefault = false,
  }) async {
    if (failUpdateAddressWith != null) throw failUpdateAddressWith!;
    final index = _addresses.indexWhere((a) => a.id == address.id);
    if (index == -1) throw StateError('Address not found: ${address.id}');
    _addresses[index] = _addresses[index].copyWith(
      label: address.label,
      fullName: address.fullName,
      phoneNumber: address.phoneNumber,
      addressLine1: address.addressLine1,
      addressLine2: address.addressLine2,
      city: address.city,
      provinceOrState: address.provinceOrState,
      postalCode: address.postalCode,
    );
    if (makeDefault) _defaultId = address.id;
    notifyListeners();
  }

  @override
  Future<void> setDefaultAddress(String addressId) async {
    if (failSetDefaultAddressWith != null) throw failSetDefaultAddressWith!;
    if (!_addresses.any((a) => a.id == addressId)) {
      throw StateError('Address not found: $addressId');
    }
    _defaultId = addressId;
    notifyListeners();
  }

  @override
  Future<void> deleteAddress(String addressId) async {
    if (failDeleteAddressWith != null) throw failDeleteAddressWith!;
    final wasDefault = _defaultId == addressId;
    _addresses.removeWhere((a) => a.id == addressId);
    if (wasDefault) {
      if (_addresses.isEmpty) {
        _defaultId = null;
      } else {
        final sorted = List<AddressModel>.from(_addresses)
          ..sort((a, b) {
            final byDate = a.createdAt.compareTo(b.createdAt);
            return byDate != 0 ? byDate : a.id.compareTo(b.id);
          });
        _defaultId = sorted.first.id;
      }
    }
    notifyListeners();
  }

  @visibleForTesting
  void debugSetAddresses(List<AddressModel> addresses, {String? defaultId}) {
    _addresses
      ..clear()
      ..addAll(addresses);
    _defaultId =
        defaultId ??
        (addresses.isEmpty
            ? null
            : addresses
                  .firstWhere((a) => a.isDefault, orElse: () => addresses.first)
                  .id);
    notifyListeners();
  }
}
