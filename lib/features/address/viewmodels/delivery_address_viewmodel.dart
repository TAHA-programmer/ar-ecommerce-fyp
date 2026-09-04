import 'package:flutter/foundation.dart';
import '../../../app/viewmodels/customer_address_state.dart';

class DeliveryAddressViewModel extends ChangeNotifier {
  final CustomerAddressState _addressState;

  DeliveryAddressViewModel(this._addressState) {
    _addressState.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _addressState.removeListener(notifyListeners);
    super.dispose();
  }

  bool get isEmpty => _addressState.addresses.isEmpty;

  bool get hasSelectedAddress => _addressState.selectedAddressId != null;

  void selectAddress(String id) {
    _addressState.selectAddress(id);
  }

  /// Returns `null` on success or a clean, `AppToast`-ready error message.
  Future<String?> setDefault(String id) => _addressState.setDefaultAddress(id);

  Future<String?> deleteAddress(String id) => _addressState.deleteAddress(id);
}
