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

    test('Phase 9.2 R6 — Tier 1 is genuinely implemented in this build', () {
      expect(kTier1Implemented, isTrue);
    });

    test(
      'ARCore-capable device (camera + GLES3 + ARCore available) → Tier 1',
      () {
        final d = decideRoomArTier(infinix.copyWith(arCoreAvailable: true));
        expect(d.tier, RoomArTier.tier1Arcore);
        expect(d.reason, 'arcore-available');
      },
    );

    test('ARCore available but camera permanently denied → falls through to '
        'Tier 3, never Tier 1 (ARCore owns the camera directly, same as '
        'Tier 2)', () {
      final d = decideRoomArTier(
        infinix.copyWith(
          arCoreAvailable: true,
          cameraPermission: RoomArCameraPermission.permanentlyDenied,
        ),
      );
      expect(d.tier, isNot(RoomArTier.tier1Arcore));
      expect(d.tier, RoomArTier.tier3Preview);
    });

    test('ARCore available but no OpenGL ES 3.0 → unsupported, never Tier 1 '
        '(the Filament product overlay needs GLES3 too)', () {
      final d = decideRoomArTier(
        infinix.copyWith(
          arCoreAvailable: true,
          hasOpenGles3: false,
          markerEngineReady: false,
        ),
      );
      expect(d.tier, isNot(RoomArTier.tier1Arcore));
      expect(d.tier, RoomArTier.unsupported);
    });

    test('ARCore available but no camera hardware at all → falls through, '
        'never Tier 1', () {
      final d = decideRoomArTier(
        infinix.copyWith(arCoreAvailable: true, hasCamera: false),
      );
      expect(d.tier, isNot(RoomArTier.tier1Arcore));
    });

    test('ARCore unavailable on this device/session → Tier 2 (unchanged '
        'pre-R6 behaviour)', () {
      final d = decideRoomArTier(infinix.copyWith(arCoreAvailable: false));
      expect(d.tier, RoomArTier.tier2Marker);
    });

    test('the unknown-device default never reports ARCore available, so it '
        'still routes to Tier 2', () {
      expect(RoomArDeviceCapabilities.unknown.arCoreAvailable, isFalse);
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
