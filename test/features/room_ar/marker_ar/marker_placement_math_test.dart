import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/room_ar/marker_ar/utils/marker_placement_math.dart';

void main() {
  // Camera looking straight down at the marker from 1.0 m (same convention as
  // cube_projector_test.dart): marker +Z points up toward the camera, so
  //   marker X -> camera X,  marker Y -> camera -Y,  marker Z -> camera -Z.
  const rTopDown = <double>[1, 0, 0, 0, -1, 0, 0, 0, -1];
  const tTopDown = <double>[0, 0, 1];

  group('CropMap (FILL_CENTER)', () {
    test(
      'portrait surface taller than the image crops width, keeps height',
      () {
        final c = CropMap(
          surfaceW: 1080,
          surfaceH: 2400,
          imgW: 960,
          imgH: 1280,
        );
        // scale = max(1080/960, 2400/1280) = max(1.125, 1.875) = 1.875
        expect(c.scale, closeTo(1.875, 1e-9));
        expect(c.offX, closeTo((1080 - 960 * 1.875) / 2, 1e-6)); // -360
        expect(c.offY, closeTo(0, 1e-6));
        // surface centre -> image centre, and back.
        final (u, v) = c.surfaceToImage(540, 1200);
        expect(u, closeTo(480, 1e-6));
        expect(v, closeTo(640, 1e-6));
        final (sx, sy) = c.imageToSurface(480, 640);
        expect(sx, closeTo(540, 1e-6));
        expect(sy, closeTo(1200, 1e-6));
      },
    );

    test('surface wider than the image crops height, keeps width', () {
      final c = CropMap(surfaceW: 2000, surfaceH: 1000, imgW: 960, imgH: 1280);
      // scale = max(2000/960, 1000/1280) = 2.08333
      expect(c.scale, closeTo(2000 / 960, 1e-9));
      expect(c.offX, closeTo(0, 1e-6));
      expect(c.offY, closeTo((1000 - 1280 * (2000 / 960)) / 2, 1e-6));
      final (u, v) = c.surfaceToImage(1000, 500);
      expect(u, closeTo(480, 1e-6));
      expect(v, closeTo(640, 1e-6));
    });

    test('imageInView flags pixels cropped away on the long axis', () {
      final c = CropMap(surfaceW: 1080, surfaceH: 2400, imgW: 960, imgH: 1280);
      expect(c.imageInView(480, 640), isTrue); // centre
      expect(c.imageInView(0, 640), isFalse); // left edge is cropped off
      expect(c.imageInView(960, 640), isFalse); // right edge is cropped off
      expect(c.imageInView(480, 0), isTrue); // full height is kept
    });
  });

  group('screenToMarkerFloor', () {
    // identity crop: surface == image, principal point at the centre.
    final idCrop = CropMap(
      surfaceW: 720,
      surfaceH: 1280,
      imgW: 720,
      imgH: 1280,
    );
    const fx = 1000.0, fy = 1000.0;

    test('tap at the surface centre lands on the marker origin', () {
      final h = screenToMarkerFloor(
        sx: 360,
        sy: 640,
        crop: idCrop,
        fx: fx,
        fy: fy,
        r: rTopDown,
        t: tTopDown,
      )!;
      expect(h.offX, closeTo(0, 1e-9));
      expect(h.offZ, closeTo(0, 1e-9));
      expect(h.radius, closeTo(0, 1e-9));
      expect(h.rangeM, closeTo(1.0, 1e-9));
    });

    test(
      '100 px right of centre => 0.10 m along marker +X (fx=1000, z=1m)',
      () {
        final h = screenToMarkerFloor(
          sx: 460,
          sy: 640,
          crop: idCrop,
          fx: fx,
          fy: fy,
          r: rTopDown,
          t: tTopDown,
        )!;
        expect(h.offX, closeTo(0.10, 1e-9));
        expect(h.offZ, closeTo(0, 1e-9));
      },
    );

    test('the FILL_CENTER crop is applied to the tap coordinate', () {
      // surface 1080x2400 over a 960x1280 image (principal point 480,640).
      final crop = CropMap(
        surfaceW: 1080,
        surfaceH: 2400,
        imgW: 960,
        imgH: 1280,
      );
      final h = screenToMarkerFloor(
        sx: 540, // surface centre -> image centre despite the -360 px x-crop
        sy: 1200,
        crop: crop,
        fx: fx,
        fy: fy,
        r: rTopDown,
        t: tTopDown,
      )!;
      expect(h.offX, closeTo(0, 1e-9));
      expect(h.offZ, closeTo(0, 1e-9));
    });

    test('intersection behind the camera is rejected', () {
      // marker origin 1 m *behind* the camera along its optical axis.
      final h = screenToMarkerFloor(
        sx: 360,
        sy: 640,
        crop: idCrop,
        fx: fx,
        fy: fy,
        r: rTopDown,
        t: const <double>[0, 0, -1],
      );
      expect(h, isNull);
    });

    test('near-parallel (grazing) ray is rejected', () {
      // Pose whose floor normal maps to camera +X: the centre ray (~+Z) is
      // perpendicular to the normal -> denominator ~ 0.
      const rEdgeOn = <double>[0, 0, 1, 0, -1, 0, 1, 0, 0];
      final h = screenToMarkerFloor(
        sx: 360,
        sy: 640,
        crop: idCrop,
        fx: fx,
        fy: fy,
        r: rEdgeOn,
        t: const <double>[0, 0, 2],
      );
      expect(h, isNull);
    });

    test('an oblique pose still solves and stays on the floor plane', () {
      // top-down pose tilted 30 deg forward about camera X: R = Rx(a)·Rx(180).
      const a = 30 * math.pi / 180;
      final ca = math.cos(a), sa = math.sin(a);
      final r = <double>[
        1.0, 0.0, 0.0, //
        0.0, -ca, sa, //
        0.0, -sa, -ca,
      ];
      final t = <double>[0.0, 0.0, 2.0];
      final h = screenToMarkerFloor(
        sx: 360,
        sy: 640,
        crop: idCrop,
        fx: fx,
        fy: fy,
        r: r,
        t: t,
      );
      expect(h, isNotNull);
      // recovered marker Z is ~0 (the internal planeToleranceM guard passed).
      expect(h!.radius, lessThan(5.0));
      expect(h.rangeM, greaterThan(1.0));
    });
  });

  group('clampToRadius (0.6 m safe placement)', () {
    test('a point outside the disc is pulled to the rim, direction kept', () {
      final (x, z) = clampToRadius(0.9, 0.0, 0.6);
      expect(x, closeTo(0.6, 1e-9));
      expect(z, closeTo(0.0, 1e-9));
    });

    test('a point inside the disc is unchanged', () {
      final (x, z) = clampToRadius(0.3, 0.4, 0.6); // r = 0.5
      expect(x, closeTo(0.3, 1e-9));
      expect(z, closeTo(0.4, 1e-9));
    });

    test('the origin is unchanged (no divide-by-zero)', () {
      final (x, z) = clampToRadius(0, 0, 0.6);
      expect(x, 0);
      expect(z, 0);
    });

    test('diagonal clamp preserves the angle and lands on the rim', () {
      final (x, z) = clampToRadius(1.0, 1.0, 0.6);
      expect(math.sqrt(x * x + z * z), closeTo(0.6, 1e-9));
      expect(x, closeTo(z, 1e-9));
    });
  });

  group('cameraInMarkerFrame', () {
    test('identity rotation: C = -t', () {
      final (x, y, z) = cameraInMarkerFrame(
        const <double>[1, 0, 0, 0, 1, 0, 0, 0, 1],
        const <double>[1, 2, 3],
      );
      expect(x, closeTo(-1, 1e-9));
      expect(y, closeTo(-2, 1e-9));
      expect(z, closeTo(-3, 1e-9));
    });

    test('top-down pose: camera is 1 m up the marker +Z axis', () {
      final (x, y, z) = cameraInMarkerFrame(rTopDown, tTopDown);
      expect(x, closeTo(0, 1e-9));
      expect(y, closeTo(0, 1e-9));
      expect(z, closeTo(1.0, 1e-9));
    });
  });

  group('faceCameraYaw', () {
    test('front vector points at the camera ground position', () {
      final r = const <double>[1, 0, 0, 0, 1, 0, 0, 0, 1]; // identity
      final t = const <double>[-2, 3, 5]; // camera at marker (2, -3, -5)
      final yaw = faceCameraYaw(r: r, t: t);
      // front(yaw) = (-sin yaw, cos yaw) must be parallel to (dx, dy)=(2,-3).
      final fxv = -math.sin(yaw), fyv = math.cos(yaw);
      final n = math.sqrt(2 * 2 + 3.0 * 3.0);
      expect(fxv, closeTo(2 / n, 1e-9));
      expect(fyv, closeTo(-3 / n, 1e-9));
    });

    test('respects the chair offset when computing the direction', () {
      final r = const <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];
      final t = const <double>[0, 0, 5]; // camera at marker (0, 0, -5)
      // chair pushed to (+0.5, 0): direction to camera ground pos is (-0.5, 0).
      final yaw = faceCameraYaw(r: r, t: t, offX: 0.5, offZ: 0.0);
      final fxv = -math.sin(yaw), fyv = math.cos(yaw);
      expect(fxv, closeTo(-1.0, 1e-9));
      expect(fyv, closeTo(0.0, 1e-9));
    });

    test('camera directly overhead returns the fallback yaw', () {
      final yaw = faceCameraYaw(r: rTopDown, t: tTopDown, fallbackYaw: 0.77);
      expect(yaw, 0.77);
    });
  });

  group('wrapPi', () {
    test('wraps into (-pi, pi]', () {
      expect(wrapPi(0), 0);
      expect(wrapPi(math.pi), closeTo(math.pi, 1e-9));
      expect(wrapPi(math.pi + 0.1), closeTo(-math.pi + 0.1, 1e-9));
      expect(wrapPi(-math.pi - 0.1), closeTo(math.pi - 0.1, 1e-9));
      expect(wrapPi(3 * math.pi), closeTo(math.pi, 1e-9));
    });
  });

  group('tap-to-place + auto-face integration', () {
    test(
      'tap oblique, clamp, then face: chair inside the disc, front at camera',
      () {
        final idCrop = CropMap(
          surfaceW: 720,
          surfaceH: 1280,
          imgW: 720,
          imgH: 1280,
        );
        // top-down pose tilted 35 deg forward: R = Rx(a)·Rx(180).
        const a = 35 * math.pi / 180;
        final ca = math.cos(a), sa = math.sin(a);
        final r = <double>[1.0, 0.0, 0.0, 0.0, -ca, sa, 0.0, -sa, -ca];
        final t = <double>[0.0, 0.3, 2.2];
        final hit = screenToMarkerFloor(
          sx: 360,
          sy: 900, // low on screen -> further out on the floor
          crop: idCrop,
          fx: 1000,
          fy: 1000,
          r: r,
          t: t,
        );
        expect(hit, isNotNull);
        final (cxp, czp) = clampToRadius(hit!.offX, hit.offZ, 0.6);
        expect(math.sqrt(cxp * cxp + czp * czp), lessThanOrEqualTo(0.6 + 1e-9));

        final yaw = faceCameraYaw(r: r, t: t, offX: cxp, offZ: czp);
        // the chair front (-sin yaw, cos yaw) must aim at the camera's ground
        // position relative to the (clamped) chair location.
        final (camX, camY, _) = cameraInMarkerFrame(r, t);
        final dx = camX - cxp, dy = camY - czp;
        final dn = math.sqrt(dx * dx + dy * dy);
        final fxv = -math.sin(yaw), fyv = math.cos(yaw);
        expect(fxv * dx / dn + fyv * dy / dn, closeTo(1.0, 1e-9)); // parallel
      },
    );
  });
}
