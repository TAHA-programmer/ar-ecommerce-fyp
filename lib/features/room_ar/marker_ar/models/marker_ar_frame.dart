// Per-frame data streamed from the native detector over the events channel.
//
// Field mapping is a verbatim port of the physically-approved
// `_marker_ar_poc/lib/ar/marker_channel.dart` — the honest four-state tracking
// model in particular is unchanged.

/// Legacy coarse state (kept for the "model visible this frame?" signal).
enum MarkerArStatus { starting, searching, detected, lost, error }

/// The honest tracking state from the native detector:
///  * [tracking]  — marker genuinely detected this frame (or within ~0.3 s);
///  * [holding]   — marker temporarily missed; last pose frozen (≤ ~1.2 s);
///  * [tooFar]    — a marker is visible but too few pixels to trust; not tracked;
///  * [searching] — nothing; detection genuinely ended.
enum MarkerTrackState { tracking, holding, tooFar, searching }

/// Solved marker pose. [r] is a row-major 3×3 rotation (9 values), [t] the
/// translation in metres (3 values). `Pcam = R·Pmarker + t` (OpenCV frame).
class MarkerPose {
  final List<double> r;
  final List<double> t;
  const MarkerPose(this.r, this.t);
}

class MarkerArFrame {
  final MarkerArStatus status;
  final MarkerTrackState track;
  final String? message;
  final double fps;
  final double detMs;
  final String pass; // "roi" | "full" | "zoom"
  final double
  heldMs; // how long the current pose has been held (0 while tracking)
  final int imgW, imgH;
  final List<double> k; // fx, fy, cx, cy
  final double focalMm;
  final List<double>? r; // 9
  final List<double>? t; // 3
  final List<double>? corners; // 8 (image px)
  final double? distM;
  final double markerSizeMm;
  final double
  markerSidePx; // detected marker side length in analysis px (0 if none)

  const MarkerArFrame._({
    required this.status,
    this.track = MarkerTrackState.searching,
    this.message,
    this.fps = 0,
    this.detMs = 0,
    this.pass = 'full',
    this.heldMs = 0,
    this.imgW = 0,
    this.imgH = 0,
    this.k = const [0, 0, 0, 0],
    this.focalMm = 0,
    this.r,
    this.t,
    this.corners,
    this.distM,
    this.markerSizeMm = 160,
    this.markerSidePx = 0,
  });

  /// A valid pose to adopt this frame, or null.
  MarkerPose? get pose => (r != null && t != null) ? MarkerPose(r!, t!) : null;

  bool get hasIntrinsics => k[0] > 0 && imgW > 0 && imgH > 0;

  factory MarkerArFrame.fromMap(Map<dynamic, dynamic> m) {
    final status = switch ((m['state'] ?? 'searching').toString()) {
      'detected' => MarkerArStatus.detected,
      'error' => MarkerArStatus.error,
      _ => MarkerArStatus.searching,
    };
    final track = switch ((m['track'] ?? '').toString()) {
      'tracking' => MarkerTrackState.tracking,
      'holding' => MarkerTrackState.holding,
      'toofar' => MarkerTrackState.tooFar,
      _ => MarkerTrackState.searching,
    };
    List<double>? dl(dynamic v) => v == null
        ? null
        : (v as List).map((e) => (e as num).toDouble()).toList(growable: false);
    return MarkerArFrame._(
      status: status,
      track: track,
      message: m['message']?.toString(),
      fps: (m['fps'] as num?)?.toDouble() ?? 0,
      detMs: (m['detMs'] as num?)?.toDouble() ?? 0,
      pass: (m['pass'] ?? 'full').toString(),
      heldMs: (m['heldMs'] as num?)?.toDouble() ?? 0,
      imgW: (m['imgW'] as num?)?.toInt() ?? 0,
      imgH: (m['imgH'] as num?)?.toInt() ?? 0,
      k: dl(m['K']) ?? const [0, 0, 0, 0],
      focalMm: (m['focalMm'] as num?)?.toDouble() ?? 0,
      r: dl(m['R']),
      t: dl(m['t']),
      corners: dl(m['corners']),
      distM: (m['distM'] as num?)?.toDouble(),
      markerSizeMm: (m['markerSizeMm'] as num?)?.toDouble() ?? 160,
      markerSidePx: (m['markerSidePx'] as num?)?.toDouble() ?? 0,
    );
  }

  static const MarkerArFrame starting = MarkerArFrame._(
    status: MarkerArStatus.starting,
  );
}
