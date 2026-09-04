import '../../../core/models/auth/user_profile_model.dart';

/// Reads and writes the `users/{uid}` Firestore profile document.
///
/// This is deliberately separate from [AuthRepository]: [AuthRepository]
/// owns Firebase Authentication identity (sign in/up/out, session), while
/// this owns the Firestore profile record that mirrors a subset of that
/// identity for display purposes. Never the source of authorization - see
/// [UserProfileModel]'s `role` field doc comment.
abstract class UserProfileRepository {
  /// Creates the profile document for a brand-new account. Always writes
  /// `role: 'customer'` - there is no code path that lets a client create
  /// itself as `superAdmin`.
  Future<void> createProfile({
    required String uid,
    required String email,
    required String displayName,
    required String phone,
  });

  /// Returns `null` if no profile document exists for [uid].
  Future<UserProfileModel?> getProfile(String uid);

  /// Updates only the editable personal fields. Never writes `role`,
  /// `email`, `uid`, or `createdAt` - both this method's implementation and
  /// `firestore.rules` enforce that boundary independently.
  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String phone,
  });

  /// Updates only `avatarStoragePath` (Phase 8.7) - a Storage OBJECT PATH,
  /// never a download URL (see [UserProfileModel.avatarStoragePath]'s doc
  /// comment). Pass `null` to clear the avatar (e.g. after deleting the
  /// underlying Storage object). Kept as its own narrow method, distinct
  /// from [updateProfile], mirroring how `CommerceDatabase` keeps
  /// `updateStock`/`setProductActive` as separate narrow writes rather than
  /// folding every field into one generic update.
  Future<void> updateAvatarStoragePath({
    required String uid,
    required String? avatarStoragePath,
  });
}
