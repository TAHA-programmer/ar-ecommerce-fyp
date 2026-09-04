import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/services/firebase_storage_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/utils/image_upload_validator.dart';
import '../../core/utils/unique_object_name.dart';
import '../../features/profile/repositories/user_profile_repository.dart';

/// Real signed-in customer's profile, backed by the `users/{uid}` Firestore
/// document via [UserProfileRepository]. Mirrors [CommerceDatabase]'s
/// "single reactive source" pattern used elsewhere in the app.
///
/// This is wired in `app_providers.dart` as a
/// `ChangeNotifierProxyProvider3<AuthSessionState, UserProfileRepository,
/// StorageService, _>` so [loadForUser] is (re)triggered automatically
/// whenever [AuthSessionState.userId] changes - login loads the new user's
/// profile, logout clears it. This deliberately avoids a live Firestore
/// snapshot listener: the profile only changes through this app's own Edit
/// Profile flow, which already knows the new values, so a plain load-once +
/// optimistic-update-on-save is simpler and sufficient (no other device
/// concurrently edits a customer's own profile in this phase).
///
/// Phase 8.7: the avatar is real, cloud-backed, and per-uid - each signed-in
/// user's [avatarStoragePath]/[avatarBytes] come from their own `users/{uid}`
/// document via an authenticated Storage read (never a public URL, per the
/// owner+admin-only read decision - see `storage.rules`).
///
/// **Async account-isolation guard**: a single instance of this class is
/// reused across an entire app session (login -> logout -> a different
/// login), so a slow network response for User A's profile/avatar can
/// legitimately still be in flight at the exact moment User B becomes the
/// active session. Without a guard, A's late-arriving result would silently
/// overwrite B's already-loaded fields, loading flags, or avatar bytes -
/// visible cross-user data leakage, not just a cosmetic glitch. [_generation]
/// is bumped every time the active uid changes (a new uid loads, or the
/// session clears via logout); every async operation captures the
/// generation in effect when it *started* and re-checks it immediately
/// before writing any shared field back - a mismatch means a different user
/// is now active and the result is silently dropped rather than applied.
/// [uploadAvatar] additionally captures the avatar path it is about to
/// replace *before* its first `await`, so a stale upload can only ever
/// delete its own uid's previous avatar, never whatever object happens to
/// currently sit in [_avatarStoragePath] by the time it finishes (which
/// could by then belong to a different signed-in user entirely).
class CustomerProfileState extends ChangeNotifier {
  final UserProfileRepository _repository;
  final StorageService _storageService;
  String? _uid;

  /// See the class doc comment's "Async account-isolation guard" section.
  int _generation = 0;

  String _fullName = '';
  String _email = '';
  String _phoneNumber = '';
  String? _avatarStoragePath;
  Uint8List? _avatarBytes;
  bool _isAvatarLoading = false;
  bool _isLoading = false;

  /// [storageService] is an optional constructor parameter defaulting to
  /// the real [FirebaseStorageService] - the same "optional param, internal
  /// default" DI pattern used throughout this codebase (see
  /// `AdminProductFormViewModel`'s identical `storageService` parameter).
  CustomerProfileState(this._repository, {StorageService? storageService})
    : _storageService = storageService ?? FirebaseStorageService();

  String get fullName => _fullName;
  String get email => _email;
  String get phoneNumber => _phoneNumber;

  /// Storage OBJECT PATH under `users/{uid}/profile/...`, or `null` if this
  /// user has never uploaded an avatar. Never a download URL - see
  /// [UserProfileModel.avatarStoragePath]'s doc comment for why.
  String? get avatarStoragePath => _avatarStoragePath;

  /// Decoded avatar bytes, fetched via an authenticated Storage read and
  /// cached here for `Image.memory` rendering. `null` while loading (see
  /// [isAvatarLoading]) or if there is no avatar / the fetch failed - both
  /// cases render the same graceful "no avatar" placeholder, never a broken
  /// image or a crash.
  Uint8List? get avatarBytes => _avatarBytes;
  bool get isAvatarLoading => _isAvatarLoading;
  bool get isLoading => _isLoading;

  /// Loads (or clears, if [uid] is `null`) the profile for the given user.
  /// Safe to call repeatedly with the same [uid] - it is a no-op after the
  /// first successful load for that user, so wiring this from a
  /// `ChangeNotifierProxyProvider`'s `update` callback (which can fire for
  /// unrelated [AuthSessionState] changes) never causes a refetch loop.
  ///
  /// A direct User A -> User B switch (no intervening `loadForUser(null)`)
  /// clears every visible field immediately, synchronously, before the new
  /// user's data is fetched - User A's name/avatar must never remain on
  /// screen while User B's profile is still loading.
  Future<void> loadForUser(String? uid) async {
    if (uid == null) {
      if (_uid == null) return;
      _clear();
      return;
    }
    if (_uid == uid) return;

    _uid = uid;
    final generation = ++_generation;
    _fullName = '';
    _email = '';
    _phoneNumber = '';
    _avatarStoragePath = null;
    _avatarBytes = null;
    _isLoading = true;
    _isAvatarLoading = false;
    notifyListeners();

    try {
      final profile = await _repository.getProfile(uid);
      if (generation != _generation) {
        // A different user became active while this fetch was in flight -
        // drop the result, it is no longer for the current session.
        return;
      }
      if (profile != null) {
        _fullName = profile.displayName;
        _email = profile.email;
        _phoneNumber = profile.phone;
        _avatarStoragePath = profile.avatarStoragePath;
      }
    } catch (_) {
      // Leave whatever was already cleared above; Profile/Edit Profile
      // surfaces their own error via AppToast when a subsequent save
      // fails, so a silent load failure here just means blank fields
      // rather than a crash.
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        notifyListeners();
      }
    }

    if (generation != _generation) return;
    await _loadAvatarBytes(generation);
  }

  /// Fetches [avatarBytes] for the currently-loaded [_avatarStoragePath] via
  /// an authenticated Storage read. A fetch failure (network, permission,
  /// deleted object) degrades silently to the "no avatar" placeholder -
  /// mirrors [loadForUser]'s own silent-failure convention - since a broken
  /// avatar thumbnail is not worth an intrusive error toast on a passive
  /// profile screen. [generation] gates every write-back, exactly like
  /// [loadForUser] - see the class doc comment.
  Future<void> _loadAvatarBytes(int generation) async {
    final path = _avatarStoragePath;
    if (path == null) {
      if (generation == _generation) {
        _avatarBytes = null;
        notifyListeners();
      }
      return;
    }

    if (generation == _generation) {
      _isAvatarLoading = true;
      notifyListeners();
    }

    Uint8List? bytes;
    try {
      bytes = await _storageService.downloadAvatarBytes(path);
    } catch (_) {
      bytes = null;
    }

    if (generation != _generation) {
      // A different user became active while this download was in flight -
      // never paint their screen with a previous user's avatar bytes.
      return;
    }
    _avatarBytes = bytes;
    _isAvatarLoading = false;
    notifyListeners();
  }

  /// Updates the editable personal fields (name/phone only - email is fixed
  /// identity data in this phase, see `EditProfileViewModel`). Returns
  /// `null` on success or a user-friendly error message on failure.
  Future<String?> updateProfile({
    required String name,
    required String phone,
  }) async {
    final uid = _uid;
    if (uid == null) return 'You are not signed in.';
    final generation = _generation;
    try {
      await _repository.updateProfile(
        uid: uid,
        displayName: name,
        phone: phone,
      );
      if (generation == _generation) {
        _fullName = name;
        _phoneNumber = phone;
        notifyListeners();
      }
      return null;
    } catch (_) {
      return 'Could not update your profile. Please try again.';
    }
  }

  /// Uploads [file] as the signed-in customer's new avatar to
  /// `users/{uid}/profile/{uniqueObjectName}`, commits the resulting Storage
  /// path to their `users/{uid}` document, then refreshes [avatarBytes] for
  /// immediate rendering. Returns `null` on success or a clean, user-facing
  /// error message on failure (never a raw exception - see
  /// `StorageServiceException`/`ImageValidationException`).
  ///
  /// Preflight: [file] is validated (exists, supported type, under
  /// [avatarMaxUploadBytes]) BEFORE any Storage call - an oversized or
  /// unsupported selection fails immediately with a clean message rather
  /// than silently doing nothing or bouncing off a raw rules rejection.
  ///
  /// Failure handling: if the Storage upload succeeds but the Firestore
  /// commit fails, the just-uploaded (orphaned, not-yet-referenced-anywhere)
  /// object is rolled back via a best-effort delete, so a failed avatar
  /// change never leaves a dangling object AND never falsely reports
  /// success. If the commit succeeds but the immediate bytes re-fetch fails,
  /// that is NOT treated as a failure of this call - the avatar change is
  /// already durably saved; only the local preview couldn't refresh (it will
  /// on the next `loadForUser`).
  ///
  /// **Cross-user safety**: [uid] and the avatar path being replaced
  /// ([previousPathForThisUid]) are both captured synchronously, before this
  /// method's first `await` - never re-read from `_uid`/`_avatarStoragePath`
  /// afterward. If the active session changes while this upload is still in
  /// flight, the Firestore commit (scoped to the original `uid`) and the
  /// cleanup of that uid's own previous avatar still proceed correctly (they
  /// were never ambiguous), but this session's shared in-memory state
  /// (`_avatarStoragePath`/`_avatarBytes`) is only touched if [uid] is still
  /// the active session by the time the upload finishes - see the class doc
  /// comment.
  Future<String?> uploadAvatar(File file) async {
    final uid = _uid;
    if (uid == null) return 'You are not signed in.';
    final generation = _generation;
    final previousPathForThisUid = _avatarStoragePath;

    try {
      await validateImageFileForUpload(
        file,
        maxSizeBytes: avatarMaxUploadBytes,
        label: 'photo',
      );
    } on ImageValidationException catch (e) {
      return e.message;
    }

    if (generation == _generation) {
      _isAvatarLoading = true;
      notifyListeners();
    }

    String? newPath;
    try {
      final objectName = generateUniqueObjectName(
        extension: extensionFromPath(file.path),
      );
      newPath = await _storageService.uploadAvatar(
        uid: uid,
        objectName: objectName,
        file: file,
      );
      await _repository.updateAvatarStoragePath(
        uid: uid,
        avatarStoragePath: newPath,
      );
    } catch (e) {
      if (newPath != null) {
        try {
          await _storageService.deleteAvatarByPath(newPath);
        } catch (_) {
          // Best-effort rollback only.
        }
      }
      if (generation == _generation) {
        _isAvatarLoading = false;
        notifyListeners();
      }
      return e is StorageServiceException
          ? e.message
          : 'Could not update your photo. Please try again.';
    }

    // The Firestore commit for `uid` succeeded. Shared in-memory state (and
    // this session's UI) is only touched if `uid` is STILL the active
    // session - otherwise this stale upload would paint a different, now-
    // active user's screen with a photo they never chose.
    if (generation == _generation) {
      _avatarStoragePath = newPath;
      try {
        _avatarBytes = await _storageService.downloadAvatarBytes(newPath);
      } catch (_) {
        _avatarBytes = null;
      }
      _isAvatarLoading = false;
      notifyListeners();
    }

    // Cleaning up the PREVIOUS avatar is always safe regardless of whether
    // the session is still current: `previousPathForThisUid` was captured
    // for `uid` before this method's first `await`, so it can never be some
    // other user's current avatar - only ever this same uid's own old one.
    if (previousPathForThisUid != null && previousPathForThisUid != newPath) {
      try {
        await _storageService.deleteAvatarByPath(previousPathForThisUid);
      } catch (_) {
        // Best-effort cleanup only.
      }
    }

    return null;
  }

  /// Clears the session and invalidates every in-flight operation (bumping
  /// [_generation]) so a User A response that arrives after logout can never
  /// resurrect A's data or leave either loading flag stuck `true`.
  void _clear() {
    _generation++;
    _uid = null;
    _fullName = '';
    _email = '';
    _phoneNumber = '';
    _avatarStoragePath = null;
    _avatarBytes = null;
    _isLoading = false;
    _isAvatarLoading = false;
    notifyListeners();
  }
}
