import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/auth/user_profile_model.dart';
import 'user_profile_repository.dart';

class FirestoreUserProfileRepository implements UserProfileRepository {
  final FirebaseFirestore _firestore;

  FirestoreUserProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Future<void> createProfile({
    required String uid,
    required String email,
    required String displayName,
    required String phone,
  }) {
    return _users.doc(uid).set({
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'phone': phone,
      'role': 'customer',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<UserProfileModel?> getProfile(String uid) async {
    final snapshot = await _users.doc(uid).get();
    final data = snapshot.data();
    if (data == null) return null;
    return _fromMap(uid, data);
  }

  @override
  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String phone,
  }) {
    // Deliberately an `.update()` with exactly these two keys - never a
    // `.set()` - so this call can never touch `role`/`email`/`uid`/
    // `createdAt` even if a future edit accidentally widened the map.
    return _users.doc(uid).update({'displayName': displayName, 'phone': phone});
  }

  @override
  Future<void> updateAvatarStoragePath({
    required String uid,
    required String? avatarStoragePath,
  }) {
    // Deliberately an `.update()` with exactly this one key - same
    // narrow-write convention as updateProfile above.
    return _users.doc(uid).update({'avatarStoragePath': avatarStoragePath});
  }

  UserProfileModel _fromMap(String uid, Map<String, dynamic> data) {
    final createdAtValue = data['createdAt'];
    return UserProfileModel(
      uid: uid,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      role: data['role'] as String? ?? 'customer',
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : null,
      avatarStoragePath: data['avatarStoragePath'] as String?,
    );
  }
}
