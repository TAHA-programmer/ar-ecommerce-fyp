import 'dart:math' as math;

/// Pure Tier-2 Marker-AR placement math — screen-tap → marker-floor ray casting,
/// CameraX `FILL_CENTER` crop mapping, safe-radius clamping and the
/// customer-facing default yaw.
///
/// Ported **verbatim** from the physically-approved `_marker_ar_poc`
/// (`lib/ar/placement_math.dart`) — every rule here was device-validated. No
/// Flutter widgets, no plugins, no `dart:ui`, so all of it is unit-tested in
/// `test/features/room_ar/marker_ar/marker_placement_math_test.dart`.
///
/// Coordinate frames (identical to `RoomArModelRenderer.kt` + the solvePnP
/// objPoints):
///  * Marker frame — origin at the marker centre, +X right and +Y up *in the
///    printed plane*, +Z out of the sheet. The floor is the plane `Z = 0`.
///    Metres. The model's floor offset is `(offX, offZ)` = marker `(X, Y)`.
///  * Camera frame — OpenCV convention: +X right, +Y down, +Z forward.
///    `Pcam = R * Pmarker + t`, `R` row-major 3×3 (9), `t` metres (3).
///  * Analysis image — the upright post-rotation frame, `imgW × imgH` px,
///    pinhole `(fx, fy)` with the principal point at the image centre (native
///    sets `cx = imgW/2`, `cy = imgH/2`).
///  * Surface — the on-screen PlatformView, `surfaceW × surfaceH` logical px.

/// `PreviewView.ScaleType.FILL_CENTER` mapping between the upright analysis image
/// and the on-screen surface: the image is scaled by
/// `max(surfaceW/imgW, surfaceH/imgH)` and centre-cropped, so it always fills the
/// surface and the overflow on the long axis is clipped symmetrically.
class CropMap {
  final double surfaceW, surfaceH;
  final int imgW, imgH;

  /// image px → surface px (isotropic).
  final double scale;

  /// surface px of image pixel (0, 0). ≤ 0 on the cropped axis.
  final double offX, offY;

  factory CropMap({
    required double surfaceW,
    required double surfaceH,
    required int imgW,
    required int imgH,
  }) {
    final scale = math.max(surfaceW / imgW, surfaceH / imgH);
    return CropMap._(
      surfaceW,
      surfaceH,
      imgW,
      imgH,
      scale,
      (surfaceW - imgW * scale) / 2.0,
      (surfaceH - imgH * scale) / 2.0,
    );
  }

  const CropMap._(
    this.surfaceW,
    this.surfaceH,
    this.imgW,
    this.imgH,
    this.scale,
    this.offX,
    this.offY,
  );

  /// surface (logical px) → analysis-image px. Not clamped: a surface point that
  /// falls in a cropped-away band maps to an image coord outside
  /// `[0,imgW] × [0,imgH]` — the ray through it is still geometrically valid, so
  /// the caller decides what to do with it.
  (double, double) surfaceToImage(double sx, double sy) =>
      ((sx - offX) / scale, (sy - offY) / scale);

  /// analysis-image px → surface (logical px).
  (double, double) imageToSurface(double u, double v) =>
      (u * scale + offX, v * scale + offY);

  /// Whether analysis-image pixel `(u, v)` currently falls inside the surface
  /// (i.e. it was not cropped away by `FILL_CENTER`).
  bool imageInView(double u, double v) {
    final (sx, sy) = imageToSurface(u, v);
    return sx >= 0 && sx <= surfaceW && sy >= 0 && sy <= surfaceH;
  }
}

/// Where a screen-tap ray meets the marker floor plane.
class FloorHit {
  /// marker-frame X (metres) — becomes the model's `offsetX`.
  final double offX;

  /// marker-frame Y (metres) — becomes the model's `offsetZ` (floor plane).
  final double offZ;

  /// `hypot(offX, offZ)` — distance of the hit from the marker origin.
  final double radius;

  /// straight-line distance from the camera centre to the hit point (metres).
  final double rangeM;

  const FloorHit(this.offX, this.offZ, this.radius, this.rangeM);
}

/// Cast a ray from the camera centre through surface point `(sx, sy)` and
/// intersect it with the marker floor plane (marker `Z = 0`).
///
/// Returns `null` — a tap that must be rejected — when:
///  * the ray is within [parallelEpsilon] (relative) of parallel to the floor
///    (grazing angle; the solved intersection would be wildly unstable);
///  * the intersection is behind the camera (`lambda <= 0`);
///  * the recovered marker-frame Z of the hit exceeds [planeToleranceM]
///    (pose/plane inconsistency — a bad solve).
FloorHit? screenToMarkerFloor({
  required double sx,
  required double sy,
  required CropMap crop,
  required double fx,
  required double fy,
  required List<double> r,
  required List<double> t,
  double parallelEpsilon = 0.02,
  double planeToleranceM = 0.05,
}) {
  final cx = crop.imgW / 2.0;
  final cy = crop.imgH / 2.0;
  final (u, v) = crop.surfaceToImage(sx, sy);

  // Ray direction in the camera frame (pinhole back-projection).
  final dx = (u - cx) / fx;
  final dy = (v - cy) / fy;
  const dz = 1.0;
  final dLen = math.sqrt(dx * dx + dy * dy + dz * dz);

  // Floor-plane normal in the camera frame = R · (0,0,1) = 3rd column of R.
  final nx = r[2], ny = r[5], nz = r[8];
  final nLen = math.sqrt(nx * nx + ny * ny + nz * nz);

  final denom = nx * dx + ny * dy + nz * dz;
  if (denom.abs() < parallelEpsilon * dLen * nLen) return null; // near-parallel

  // Camera centre is the origin, so lambda = n·t / n·d.
  final lambda = (nx * t[0] + ny * t[1] + nz * t[2]) / denom;
  if (lambda <= 0) return null; // behind the camera

  final px = lambda * dx, py = lambda * dy, pz = lambda * dz;

  // Camera → marker frame:  Pm = Rᵀ (Pc − t).
  final ax = px - t[0], ay = py - t[1], az = pz - t[2];
  final mx = r[0] * ax + r[3] * ay + r[6] * az;
  final my = r[1] * ax + r[4] * ay + r[7] * az;
  final mz = r[2] * ax + r[5] * ay + r[8] * az;
  if (mz.abs() > planeToleranceM) return null; // inconsistent pose

  final radius = math.sqrt(mx * mx + my * my);
  final rangeM = math.sqrt(px * px + py * py + pz * pz);
  return FloorHit(mx, my, radius, rangeM);
}

/// Clamp a marker-plane point to a disc of [maxRadiusM] about the marker origin
/// (the 0.6 m safe-placement clamp). Returns the point unchanged when it is
/// already inside the disc.
(double, double) clampToRadius(double x, double z, double maxRadiusM) {
  final r = math.sqrt(x * x + z * z);
  if (r <= maxRadiusM || r == 0) return (x, z);
  final k = maxRadiusM / r;
  return (x * k, z * k);
}

/// Camera position expressed in the marker frame:  `C = −Rᵀ t`.
(double, double, double) cameraInMarkerFrame(List<double> r, List<double> t) {
  final cx = -(r[0] * t[0] + r[3] * t[1] + r[6] * t[2]);
  final cy = -(r[1] * t[0] + r[4] * t[1] + r[7] * t[2]);
  final cz = -(r[2] * t[0] + r[5] * t[1] + r[8] * t[2]);
  return (cx, cy, cz);
}

/// Yaw (radians, about the marker +Z axis) that turns the model's **front** to
/// face the camera position projected onto the floor.
///
/// At yaw 0 the model front points along marker +Y (see
/// `RoomArModelRenderer.modelMatrix`: model −Z → marker +Y). At yaw θ the front
/// points along `(−sinθ, cosθ)` in the marker plane, so the yaw that aims it at a
/// floor direction `(dx, dy)` is `atan2(−dx, dy)`.
///
/// Returns [fallbackYaw] when the camera is essentially above the model
/// (planar distance < [minPlanarDistM]) — there is no meaningful facing there.
double faceCameraYaw({
  required List<double> r,
  required List<double> t,
  double offX = 0,
  double offZ = 0,
  double fallbackYaw = 0,
  double minPlanarDistM = 0.05,
}) {
  final (cx, cy, _) = cameraInMarkerFrame(r, t);
  final dx = cx - offX;
  final dy = cy - offZ;
  if (math.sqrt(dx * dx + dy * dy) < minPlanarDistM) return fallbackYaw;
  return math.atan2(-dx, dy);
}

/// Wrap an angle to `(−π, π]`.
double wrapPi(double a) {
  const twoPi = 2 * math.pi;
  var x = a % twoPi;
  if (x > math.pi) x -= twoPi;
  if (x <= -math.pi) x += twoPi;
  return x;
}
