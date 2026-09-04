import 'dart:math';

final Random _random = Random.secure();

/// Generates a collision-resistant Storage object filename: a microsecond
/// timestamp (monotonically increasing within a single upload batch) plus a
/// random hex suffix plus an optional caller-supplied [index] (so a batch of
/// images uploaded in the same microsecond, which does happen on fast
/// devices, still sorts and never collides). Not a UUID - this project has
/// no `uuid` dependency and one isn't needed for this narrow, low-volume use
/// (a single Admin uploading a handful of images at a time).
String generateUniqueObjectName({required String extension, int index = 0}) {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final randomSuffix = _random.nextInt(0xFFFFFFFF).toRadixString(16);
  return '${timestamp}_${index}_$randomSuffix.$extension';
}

/// Best-effort file extension extraction from a local file path, defaulting
/// to `jpg` (matches `image_picker`'s typical output and `storage.rules`'
/// accepted MIME types) when the path has no recognizable extension.
String extensionFromPath(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == path.length - 1) return 'jpg';
  final ext = path.substring(dotIndex + 1).toLowerCase();
  const known = {'jpg', 'jpeg', 'png', 'webp'};
  return known.contains(ext) ? ext : 'jpg';
}
