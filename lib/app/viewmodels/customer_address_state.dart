import 'package:flutter/foundation.dart';

import '../../core/data/address_repository.dart';
import '../../features/address/models/address_model.dart';

/// Thin reactive wrapper around [AddressRepository] (Phase 8.10). Keeps the
/// same public shape ViewModels/tests have always depended on
/// (`addresses`/`selectedAddressId`/`selectedAddress`/`defaultAddress` +
/// `selectAddress`/`addAddress`/`updateAddress`/`setDefaultAddress`/
/// `deleteAddress`) so `AddressFormViewModel`/`SavedAddressesViewModel`/
/// `DeliveryAddressViewModel`/`CheckoutViewModel` and every existing test
/// built against a `MockAddressRepository`-backed instance keep working
/// unchanged in shape - only the mutating methods became `Future`-based
/// (per the Phase 8.10 requirement), returning a clean, `AppToast`-ready
/// error message (`null` on success).
///
/// All real Firestore complexity - uid isolation, the authoritative
/// default-address pointer, generation-guarded stale-callback rejection,
/// last-good-cache preservation - lives entirely in [AddressRepository]'s
/// real implementation (`FirestoreAddressRepository`). This class only adds
/// [selectedAddressId]: a purely local, session-only "which address is
/// highlighted in Delivery Address / used by Checkout right now" concept
/// that was never part of the synced schema and doesn't need to be -
/// Checkout always reads it synchronously from this class, backed by the
/// repository's already-live cache.
class CustomerAddressState extends ChangeNotifier {
  final AddressRepository _repository;
  String? _selectedAddressId;

  CustomerAddressState(this._repository) {
    _repository.addListener(_onRepositoryChanged);
    _reconcileSelection();
  }

  @override
  void dispose() {
    _repository.removeListener(_onRepositoryChanged);
    super.dispose();
  }

  bool get isLoading => _repository.isLoading;
  bool get hasError => _repository.hasError;

  List<AddressModel> get addresses => _repository.addresses;

  String? get selectedAddressId => _selectedAddressId;

  AddressModel? get selectedAddress {
    final id = _selectedAddressId;
    if (id == null) return null;
    for (final a in addresses) {
      if (a.id == id) return a;
    }
    return null;
  }

  AddressModel? get defaultAddress => _repository.defaultAddress;

  void _onRepositoryChanged() {
    _reconcileSelection();
    notifyListeners();
  }

  /// If the previously-selected address is gone (deleted on another device,
  /// or a fresh uid just loaded), falls back default -> first -> null - the
  /// Phase 8.10 requirement. Runs synchronously on every repository change,
  /// so [selectedAddress] never returns a dangling id.
  void _reconcileSelection() {
    final list = addresses;
    if (list.isEmpty) {
      _selectedAddressId = null;
      return;
    }
    final currentId = _selectedAddressId;
    if (currentId != null && list.any((a) => a.id == currentId)) return;
    final fallback = _repository.defaultAddress ?? list.first;
    _selectedAddressId = fallback.id;
  }

  void selectAddress(String id) {
    if (addresses.any((a) => a.id == id)) {
      _selectedAddressId = id;
      notifyListeners();
    }
  }

  /// Creates a new address and immediately selects it, using the real
  /// repository-allocated id (never a locally-guessed one - see
  /// [AddressRepository.addAddress]'s doc comment) and its structurally
  /// guaranteed [AddressModel.isDefault] (set atomically by the repository
  /// when [makeDefault] is `true` - never a separate follow-up call).
  /// Returns a clean error message on failure (e.g. signed out), or `null`
  /// on success.
  ///
  /// **Pre-deployment correction (found by independent review):** this used
  /// to gate the optimistic selection on `addresses.any((a) => a.id ==
  /// created.id)` - the repository's LIVE CACHE, populated only by its
  /// Firestore snapshot listener. That check could be falsely `false` even
  /// for the SAME still-signed-in user, simply because the listener hadn't
  /// delivered its next snapshot yet - silently failing to select (or
  /// default) a just-created address for no real reason. It is replaced
  /// here with [AddressRepository.generation]: captured before the write,
  /// compared after, so the ONLY reason the optimistic update is skipped is
  /// a genuine account switch mid-write - never ordinary listener latency.
  Future<String?> addAddress(
    AddressDraft draft, {
    bool makeDefault = false,
  }) async {
    final startGeneration = _repository.generation;
    try {
      final created = await _repository.addAddress(
        draft,
        makeDefault: makeDefault,
      );
      if (_repository.generation == startGeneration) {
        _selectedAddressId = created.id;
        notifyListeners();
      }
      return null;
    } catch (e) {
      return _cleanError(e);
    }
  }

  Future<String?> updateAddress(
    AddressModel address, {
    bool makeDefault = false,
  }) async {
    try {
      await _repository.updateAddress(address, makeDefault: makeDefault);
      return null;
    } catch (e) {
      return _cleanError(e);
    }
  }

  Future<String?> setDefaultAddress(String id) async {
    try {
      await _repository.setDefaultAddress(id);
      return null;
    } catch (e) {
      return _cleanError(e);
    }
  }

  Future<String?> deleteAddress(String id) async {
    try {
      await _repository.deleteAddress(id);
      return null;
    } catch (e) {
      return _cleanError(e);
    }
  }

  String _cleanError(Object e) {
    if (e is StateError) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
