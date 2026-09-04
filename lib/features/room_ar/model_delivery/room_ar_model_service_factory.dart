import 'room_ar_model_cache.dart';
import 'room_ar_model_service.dart';
import 'room_ar_model_storage_source.dart';

/// Builds the production [RoomArModelService] wired to the real Firebase
/// Storage source and the on-disk cache (the cache directory resolves
/// asynchronously via `path_provider`, which is why this is a `Future`).
///
/// Kept out of the app-wide provider graph for now: R10 has no customer entry
/// point yet, so the only consumer is the debug-only Marker-AR verification
/// surface. When "View in Room" is enabled (R15/R17) this becomes an
/// `AppProviders` entry.
class RoomArModelServiceFactory {
  RoomArModelServiceFactory._();

  static Future<RoomArModelService> open() async {
    final cache = await RoomArModelCache.open();
    await cache.cleanupTemp();
    return DefaultRoomArModelService(
      storageSource: FirebaseRoomArModelStorageSource(),
      modelCache: cache,
    );
  }
}
