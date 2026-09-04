import 'package:flutter/foundation.dart';
import '../../../app/viewmodels/customer_address_state.dart';

class SavedAddressesViewModel extends ChangeNotifier {
  final CustomerAddressState _addressState;

  SavedAddressesViewModel(this._addressState);

  bool get isEmpty => _addressState.addresses.isEmpty;

  /// Returns `null` on success or a clean, `AppToast`-ready error message.
  Future<String?> deleteAddress(String id) => _addressState.deleteAddress(id);

  Future<String?> setDefault(String id) => _addressState.setDefaultAddress(id);
}
