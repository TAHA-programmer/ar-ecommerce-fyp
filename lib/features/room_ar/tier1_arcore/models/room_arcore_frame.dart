/// Phase 9.2 R6 — Tier-1 markerless-ARCore per-frame state, decoded from the
/// native `twin_ar/room_ar/arcore/events` stream (`RoomArCoreFrameState.kt`).
///
/// Pure data + a couple of derived booleans — the ViewModel owns every UX
/// decision. Mirrors `MarkerArFrame`'s "typed decode of a native map" pattern.
class RoomArCoreFrame {
  const RoomArCoreFrame({
    required this.tracking,
    required this.trackingFailureReason,
    required this.planesFound,
    required this.hasAnchor,
    required this.anchorTracking,
    required this.justPlaced,
    required this.reticleVisible,
    this.terminalState,
    this.error,
    this.tapRejected = false,
  });

  /// `Camera.trackingState == TRACKING` this frame.
  final bool tracking;

  /// `Camera.TrackingFailureReason` name (`"NONE"` when tracking or unknown) —
  /// drives the honest scanning-guidance copy (`"Move more slowly"`, etc.).
  final String trackingFailureReason;

  /// At least one tracked horizontal (floor or table-height) surface exists.
  final bool planesFound;

  /// The customer has placed the product on a real surface.
  final bool hasAnchor;

  /// The placed anchor is still being tracked (false = tracking lost while
  /// placed — the object may be momentarily unreliable until it recovers).
  final bool anchorTracking;

  /// True only on the exact frame a NEW placement was just made (not a
  /// reposition) — lets the ViewModel fire a one-shot haptic/flash.
  final bool justPlaced;

  /// A valid placement preview point exists under the reticle right now.
  final bool reticleVisible;

  /// Non-null only for a terminal, native-reported failure this session
  /// cannot recover from without a retry: `"camera-permission"` |
  /// `"camera-unavailable"` | `"arcore-unavailable"` | `"arcore-installing"`.
  /// `null` means "still a normal in-progress AR frame".
  final String? terminalState;

  /// Human-readable detail for [terminalState] (native-authored, safe to
  /// show as-is — never a raw exception).
  final String? error;

  /// `true` for exactly one frame when a genuine *initial*-placement tap
  /// landed on a spot ARCore's real hit-test rejected (customer
  /// requirement: honest visible feedback instead of silently doing
  /// nothing — tracker §32). Never set for an ordinary reposition-drag
  /// sample landing briefly off the mapped surface.
  final bool tapRejected;

  bool get hasTerminalError => terminalState != null;

  static const RoomArCoreFrame starting = RoomArCoreFrame(
    tracking: false,
    trackingFailureReason: 'NONE',
    planesFound: false,
    hasAnchor: false,
    anchorTracking: false,
    justPlaced: false,
    reticleVisible: false,
  );

  factory RoomArCoreFrame.fromMap(Map<dynamic, dynamic> m) => RoomArCoreFrame(
    tracking: m['tracking'] as bool? ?? false,
    trackingFailureReason: m['trackingFailureReason'] as String? ?? 'NONE',
    planesFound: m['planesFound'] as bool? ?? false,
    hasAnchor: m['hasAnchor'] as bool? ?? false,
    anchorTracking: m['anchorTracking'] as bool? ?? false,
    justPlaced: m['justPlaced'] as bool? ?? false,
    reticleVisible: m['reticleVisible'] as bool? ?? false,
    terminalState: m['terminalState'] as String?,
    error: m['error'] as String?,
    tapRejected: m['tapRejected'] as bool? ?? false,
  );

  /// Honest, customer-facing scanning/tracking guidance for the current
  /// frame — never a raw native reason code.
  String get guidanceMessage {
    if (!tracking) {
      switch (trackingFailureReason) {
        case 'INSUFFICIENT_LIGHT':
          return 'Too dark to track — move to a brighter area.';
        case 'EXCESSIVE_MOTION':
          return 'Move your phone more slowly.';
        case 'INSUFFICIENT_FEATURES':
          return 'Point at a more detailed surface — plain walls/floors are '
              'hard to track.';
        case 'CAMERA_UNAVAILABLE':
          return 'Camera unavailable.';
        default:
          return 'Move your phone slowly to start scanning your room.';
      }
    }
    if (hasAnchor) {
      return anchorTracking
          ? 'Drag to move it, twist with two fingers to rotate.'
          : 'Tracking lost — hold steady to recover.';
    }
    if (planesFound) return 'Tap the highlighted area to place it there.';
    return 'Move your phone slowly over the floor to find a surface.';
  }
}
