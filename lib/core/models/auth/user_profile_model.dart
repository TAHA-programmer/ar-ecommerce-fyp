/// Canonical shape of a `users/{uid}` Firestore profile document.
///
/// [role] is a UI-convenience mirror of the Firebase ID-token custom claim
/// ONLY - it is written once at signup as `'customer'` and is never trusted
/// for authorization. Real authorization always reads the custom claim via
/// [FirebaseAuthRepository]'s role resolution, never this field. See
/// `firestore.rules` for the enforced boundary.
class UserProfileModel {
  final String uid;
  final String email;
  final String displayName;
  final String phone;
  final String role;
  final DateTime? createdAt;

  /// Phase 8.7: a Firebase Storage OBJECT PATH under
  /// `users/{uid}/profile/...` (e.g. `users/abc123/profile/171_ab.jpg`) -
  /// deliberately NEVER a download URL or token. `null` means no avatar has
  /// been uploaded yet. See `firestore.rules`' `isValidAvatarPath()` for the
  /// server-side enforcement that this can only ever point under the
  /// document owner's own uid.
  final String? avatarStoragePath;

  const UserProfileModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.phone,
    required this.role,
    this.createdAt,
    this.avatarStoragePath,
  });

  UserProfileModel copyWith({
    String? displayName,
    String? phone,
    String? avatarStoragePath,
    bool clearAvatarStoragePath = false,
  }) {
    return UserProfileModel(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      role: role,
      createdAt: createdAt,
      avatarStoragePath: clearAvatarStoragePath
          ? null
          : (avatarStoragePath ?? this.avatarStoragePath),
    );
  }
}
