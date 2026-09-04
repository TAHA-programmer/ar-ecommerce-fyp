import 'package:flutter/material.dart';
import '../../../app/viewmodels/customer_address_state.dart';
import '../models/address_model.dart';

/// The outcome of [AddressFormViewModel.save] - deliberately a real type,
/// not a bare `String?`, because "validation failed" and "saved
/// successfully" are NOT the same outcome and must never be conflated.
///
/// Pre-fix bug (found by independent review): `save()` used to return
/// `null` for BOTH a failed `Form.validate()` and a genuine success, and
/// `AddressFormView` treated any `null` as "pop the screen" - so an invalid
/// form (e.g. empty required field) navigated back exactly as if it had
/// saved, silently discarding the user's input. [AddressSaveResult]
/// structurally prevents that: the view can only ever pop on
/// [AddressSaveResult.success], never on [AddressSaveResult.validationFailed]
/// (the Form's own inline `validator` errors are already visible - no
/// separate toast is needed for that case) or [AddressSaveResult.failure]
/// (a backend/repository error - shown via `AppToast`).
enum _AddressSaveOutcome { success, validationFailed, inProgress, failure }

class AddressSaveResult {
  final _AddressSaveOutcome _outcome;
  final String? errorMessage;

  const AddressSaveResult._(this._outcome, [this.errorMessage]);

  const AddressSaveResult.success() : this._(_AddressSaveOutcome.success);
  const AddressSaveResult.validationFailed()
    : this._(_AddressSaveOutcome.validationFailed);
  const AddressSaveResult.inProgress() : this._(_AddressSaveOutcome.inProgress);
  const AddressSaveResult.failure(String message)
    : this._(_AddressSaveOutcome.failure, message);

  /// The only outcome that should ever navigate back.
  bool get shouldNavigateBack => _outcome == _AddressSaveOutcome.success;

  /// The only outcome that should ever show an `AppToast.error`.
  bool get shouldShowError => _outcome == _AddressSaveOutcome.failure;
}

class AddressFormViewModel extends ChangeNotifier {
  final CustomerAddressState _addressState;
  final AddressModel? initialAddress;

  AddressFormViewModel(this._addressState, {this.initialAddress}) {
    if (initialAddress != null) {
      labelController.text = initialAddress!.label ?? '';
      fullNameController.text = initialAddress!.fullName;
      phoneController.text = initialAddress!.phoneNumber;
      addressLine1Controller.text = initialAddress!.addressLine1;
      addressLine2Controller.text = initialAddress!.addressLine2 ?? '';
      cityController.text = initialAddress!.city;
      provinceController.text = initialAddress!.provinceOrState;
      postalCodeController.text = initialAddress!.postalCode;
      _isDefault = initialAddress!.isDefault;
    }
  }

  final formKey = GlobalKey<FormState>();

  final labelController = TextEditingController();
  final fullNameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressLine1Controller = TextEditingController();
  final addressLine2Controller = TextEditingController();
  final cityController = TextEditingController();
  final provinceController = TextEditingController();
  final postalCodeController = TextEditingController();

  bool _isDefault = false;
  bool get isDefault => _isDefault;

  void toggleDefault(bool? value) {
    if (value != null) {
      _isDefault = value;
      notifyListeners();
    }
  }

  bool get isEditing => initialAddress != null;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  /// See [AddressSaveResult]'s doc comment for why this is a real result
  /// type, not a bare `String?`. Guards against a double-submit while a
  /// save is already in flight.
  ///
  /// The "Set as default" checkbox is applied ATOMICALLY with the
  /// create/update itself (via `makeDefault:` on the repository call) -
  /// never as a separate follow-up write keyed off the local cache/listener
  /// state, which could race or target a stale selection (see
  /// `CustomerAddressState.addAddress`'s doc comment for the bug this
  /// closes).
  Future<AddressSaveResult> save() async {
    if (_isSaving) return const AddressSaveResult.inProgress();
    if (!(formKey.currentState?.validate() ?? false)) {
      return const AddressSaveResult.validationFailed();
    }

    _isSaving = true;
    notifyListeners();

    try {
      final label = labelController.text.trim().isNotEmpty
          ? labelController.text.trim()
          : null;
      final addressLine2 = addressLine2Controller.text.trim().isNotEmpty
          ? addressLine2Controller.text.trim()
          : null;

      String? error;
      if (isEditing) {
        // Built directly via the constructor, not `copyWith` - `copyWith`'s
        // `value ?? this.value` pattern cannot express "clear this optional
        // field to null" (it would just keep the old value), which editing
        // label/addressLine2 down to empty legitimately needs to do.
        final updated = AddressModel(
          id: initialAddress!.id,
          label: label,
          fullName: fullNameController.text.trim(),
          phoneNumber: phoneController.text.trim(),
          addressLine1: addressLine1Controller.text.trim(),
          addressLine2: addressLine2,
          city: cityController.text.trim(),
          provinceOrState: provinceController.text.trim(),
          postalCode: postalCodeController.text.trim(),
          isDefault: initialAddress!.isDefault,
          createdAt: initialAddress!.createdAt,
        );
        final wantsNewDefault = _isDefault && !initialAddress!.isDefault;
        error = await _addressState.updateAddress(
          updated,
          makeDefault: wantsNewDefault,
        );
      } else {
        final draft = AddressDraft(
          label: label,
          fullName: fullNameController.text.trim(),
          phoneNumber: phoneController.text.trim(),
          addressLine1: addressLine1Controller.text.trim(),
          addressLine2: addressLine2,
          city: cityController.text.trim(),
          provinceOrState: provinceController.text.trim(),
          postalCode: postalCodeController.text.trim(),
        );
        // makeDefault is passed through unconditionally - the repository
        // transaction itself decides "first address always becomes
        // default regardless of this flag" vs. "a later address only
        // becomes default if this flag is true", atomically, in the SAME
        // write as the creation. No separate follow-up call, no listener
        // dependency.
        error = await _addressState.addAddress(draft, makeDefault: _isDefault);
      }

      if (error != null) return AddressSaveResult.failure(error);
      return const AddressSaveResult.success();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    labelController.dispose();
    fullNameController.dispose();
    phoneController.dispose();
    addressLine1Controller.dispose();
    addressLine2Controller.dispose();
    cityController.dispose();
    provinceController.dispose();
    postalCodeController.dispose();
    super.dispose();
  }
}
