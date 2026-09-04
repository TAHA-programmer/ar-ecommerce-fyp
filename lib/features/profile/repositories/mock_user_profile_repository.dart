import '../../../core/models/auth/user_profile_model.dart';
import 'user_profile_repository.dart';

/// In-memory test/dev double, mirroring [MockAuthRepository]'s role in the
/// auth feature. Not used in production - `app_providers.dart` always wires
/// [FirestoreUserProfileRepository] there.
class MockUserProfileRepository implements UserProfileRepository {
  final Map<String, UserProfileModel> _profiles;

  MockUserProfileRepository({Map<String, UserProfileModel>? seed})
    : _profiles = seed != null ? Map.of(seed) : {};

  @override
  Future<void> createProfile({
    required String uid,
    required String email,
    required String displayName,
    required String phone,
  }) async {
    _profiles[uid] = UserProfileModel(
      uid: uid,
      email: email,
      displayName: displayName,
      phone: phone,
      role: 'customer',
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<UserProfileModel?> getProfile(String uid) async => _profiles[uid];

  @override
  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String phone,
  }) async {
    final existing = _profiles[uid];
    if (existing == null) return;
    _profiles[uid] = existing.copyWith(displayName: displayName, phone: phone);
  }

  @override
  Future<void> updateAvatarStoragePath({
    required String uid,
    required String? avatarStoragePath,
  }) async {
    final existing = _profiles[uid];
    if (existing == null) return;
    _profiles[uid] = existing.copyWith(
      avatarStoragePath: avatarStoragePath,
      clearAvatarStoragePath: avatarStoragePath == null,
    );
  }
}
