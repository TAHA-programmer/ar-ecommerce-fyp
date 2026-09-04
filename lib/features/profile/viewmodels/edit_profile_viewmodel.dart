import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../app/viewmodels/customer_profile_state.dart';

class EditProfileViewModel extends ChangeNotifier {
  final CustomerProfileState _profileState;

  late String draftFullName;

  /// Display-only - see `EditProfileView`, where the email field is
  /// rendered `enabled: false`. There is no `updateEmail`/setter here:
  /// email is fixed identity data in this phase (no Firebase email-change
  /// flow implemented), so nothing in this ViewModel can ever mutate it.
  final String email;
  late String draftPhoneNumber;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _nameError;
  String? _phoneError;
  String? _saveError;

  String? get nameError => _nameError;
  String? get phoneError => _phoneError;

  /// Set only when [saveChanges] returns `false` due to a repository/
  /// network failure (as opposed to a field-validation failure, which is
  /// surfaced through [nameError]/[phoneError] instead).
  String? get saveError => _saveError;

  /// Phase 8.7: the avatar is uploaded immediately on pick (via
  /// [uploadAvatar]), independent of the name/phone "Save Changes" flow -
  /// it is its own distinct action (a Storage upload + Firestore commit),
  /// not a draft staged for the same "Save Changes" tap. This intentionally
  /// diverges from the pre-8.7 behavior (where a picked photo was staged
  /// and only committed when Save Changes was tapped, discardable via
  /// Cancel) because a cloud upload cannot be cheaply "discarded" the way an
  /// in-memory local-file path could - see
  /// `09_BACKEND_INTEGRATION_PLAN.md`, Phase 8.7 implementation record, for
  /// the full rationale. The screen's layout is unchanged; only this one
  /// piece of interaction timing differs.
  Uint8List? get avatarBytes => _profileState.avatarBytes;

  bool _isAvatarUploading = false;
  bool get isAvatarUploading => _isAvatarUploading;

  String? _avatarError;
  String? get avatarError => _avatarError;

  EditProfileViewModel(this._profileState) : email = _profileState.email {
    draftFullName = _profileState.fullName;
    draftPhoneNumber = _profileState.phoneNumber;
  }

  void updateName(String name) {
    draftFullName = name;
    _nameError = null;
    notifyListeners();
  }

  void updatePhone(String phone) {
    draftPhoneNumber = phone;
    _phoneError = null;
    notifyListeners();
  }

  /// Uploads [file] as the new avatar immediately - see [avatarBytes]' doc
  /// comment for why this is decoupled from [saveChanges]. Errors are
  /// surfaced via [avatarError] (`AppToast` at the View layer), never
  /// thrown.
  Future<void> uploadAvatar(File file) async {
    _avatarError = null;
    _isAvatarUploading = true;
    notifyListeners();

    final error = await _profileState.uploadAvatar(file);

    _isAvatarUploading = false;
    _avatarError = error;
    notifyListeners();
  }

  /// Matches the `users/{uid}.phone` Firestore rule exactly (Phase 8.12): a
  /// standard Pakistani local mobile number - exactly 11 digits, digits
  /// only, starting with `03` (e.g. `03001234567`).
  static final RegExp _pakistaniMobile = RegExp(r'^03[0-9]{9}$');

  bool _validate() {
    bool isValid = true;
    _nameError = null;
    _phoneError = null;

    // Phase 8.12: keep these compatible with the hardened
    // `users/{uid}.displayName`/`phone` Firestore rules (displayName 1-100,
    // non-whitespace-only; phone = a Pakistani local mobile ^03[0-9]{9}$) so
    // an invalid edit shows a clear field error instead of a Firebase
    // permission-denied on save.
    final name = draftFullName.trim();
    final phone = draftPhoneNumber.trim();

    if (name.isEmpty) {
      _nameError = 'Full name is required';
      isValid = false;
    } else if (name.length > 100) {
      _nameError = 'Full name must be 100 characters or fewer';
      isValid = false;
    }

    if (phone.isEmpty) {
      _phoneError = 'Phone number is required';
      isValid = false;
    } else if (!_pakistaniMobile.hasMatch(phone)) {
      _phoneError = 'Enter an 11-digit mobile number starting with 03.';
      isValid = false;
    }

    notifyListeners();
    return isValid;
  }

  Future<bool> saveChanges() async {
    _saveError = null;
    if (!_validate()) return false;

    _isLoading = true;
    notifyListeners();

    final error = await _profileState.updateProfile(
      name: draftFullName.trim(),
      phone: draftPhoneNumber.trim(),
    );

    _isLoading = false;

    if (error != null) {
      _saveError = error;
      notifyListeners();
      return false;
    }

    notifyListeners();
    return true;
  }
}
