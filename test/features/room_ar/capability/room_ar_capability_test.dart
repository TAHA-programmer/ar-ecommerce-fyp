import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/room_ar/capability/room_ar_capability.dart';

void main() {
  const infinix = RoomArDeviceCapabilities(
    hasCamera: true,
    hasOpenGles3: true,
    markerEngineReady: true,
    arCoreAvailable: false,
    cameraPermission: RoomArCameraPermission.granted,
  );

  group('decideRoomArTier — deterministic', () {
    test('Infinix Hot 40 (camera + GLES3 + OpenCV, no ARCore) → Tier 2', () {
      final d = decideRoomArTier(infinix);
      expect(d.tier, RoomArTier.tier2Marker);
    });

    test('camera permission not yet decided still routes to Tier 2', () {
      final d = decideRoomArTier(
        infinix.copyWith(cameraPermission: RoomArCameraPermission.denied),
      );
      expect(d.tier, RoomArTier.tier2Marker);
    });

    test('camera permanently denied → Tier 3 (never a camera dead end)', () {
      final d = decideRoomArTier(
        infinix.copyWith(
          cameraPermission: RoomArCameraPermission.permanentlyDenied,
        ),
      );
      expect(d.tier, RoomArTier.tier3Preview);
      expect(d.reason, 'camera-permission-blocked');
    });

    test('no camera hardware → Tier 3', () {
      final d = decideRoomArTier(infinix.copyWith(hasCamera: false));
      expect(d.tier, RoomArTier.tier3Preview);
      expect(d.reason, 'no-camera');
    });

    test('marker engine (OpenCV) failed to load → Tier 3', () {
      final d = decideRoomArTier(infinix.copyWith(markerEngineReady: false));
      expect(d.tier, RoomArTier.tier3Preview);
      expect(d.reason, 'marker-engine-unavailable');
    });

    test('no OpenGL ES 3.0 → unsupported (no tier can run)', () {
      final d = decideRoomArTier(
        infinix.copyWith(hasOpenGles3: false, markerEngineReady: false),
      );
      expect(d.tier, RoomArTier.unsupported);
    });

    test('Tier 1 is never selected while R6 is unimplemented, '
        'even if ARCore reports available', () {
      // kTier1Implemented is false for this build.
      expect(kTier1Implemented, isFalse);
      final d = decideRoomArTier(infinix.copyWith(arCoreAvailable: true));
      expect(d.tier, isNot(RoomArTier.tier1Arcore));
      expect(d.tier, RoomArTier.tier2Marker); // falls through to a real tier
    });

    test('the unknown-device default routes to Tier 2 (its own handling '
        'takes over)', () {
      expect(
        decideRoomArTier(RoomArDeviceCapabilities.unknown).tier,
        RoomArTier.tier2Marker,
      );
    });
  });
}
