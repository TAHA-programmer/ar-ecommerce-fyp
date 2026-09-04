// Phase 9.2 R8 — Room-AR runtime tier routing.
//
// Pure model + decision logic (no platform calls) so it is fully unit-testable.
// `RoomArCapabilityService` fills `RoomArDeviceCapabilities` from the real
// device; `decideRoomArTier` turns that into exactly one usable tier.

/// The three Room-AR delivery tiers, plus an honest "nothing usable" outcome.
enum RoomArTier {
  /// ARCore markerless. **Not implemented in this build (R6).** Never selected
  /// until [kTier1Implemented] is flipped on.
  tier1Arcore,

  /// OpenCV Marker AR — the physically-approved path (Infinix Hot 40).
  tier2Marker,

  /// Interactive 3D Preview — no camera, no marker. The safe fallback whenever
  /// camera AR is unavailable / unsupported / denied / cannot run.
  tier3Preview,

  /// The device can't run any Room-AR experience (no OpenGL ES 3.0).
  unsupported,
}

/// Compile-time gate for Tier 1. R6 is a later pass; until then routing must
/// never pick a nonexistent experience, so this stays `false` and the Tier-1
/// branch in [decideRoomArTier] is dead — flipping this is all R6 needs here.
const bool kTier1Implemented = false;

/// Runtime camera-permission state relevant to tier routing.
enum RoomArCameraPermission {
  granted,

  /// Soft-denied — the customer can still be asked (first run, "deny once").
  /// Tier 2 is still offered; its own screen prompts, and drops to Tier 3 if
  /// the customer declines there.
  denied,

  /// "Don't ask again" / blocked by policy — the camera is off-limits, so
  /// Tier 2 is not offered and routing goes straight to Tier 3.
  permanentlyDenied,

  restricted,
}

/// A snapshot of what this device can currently do for Room AR.
class RoomArDeviceCapabilities {
  const RoomArDeviceCapabilities({
    required this.hasCamera,
    required this.hasOpenGles3,
    required this.markerEngineReady,
    required this.arCoreAvailable,
    required this.cameraPermission,
  });

  /// A rear/any camera exists (`PackageManager.FEATURE_CAMERA_ANY`).
  final bool hasCamera;

  /// OpenGL ES 3.0 — required by Filament for both Tier 2 and Tier 3.
  final bool hasOpenGles3;

  /// The OpenCV ArUco engine loaded (`OpenCVLoader.initLocal()`), required by
  /// Tier 2.
  final bool markerEngineReady;

  /// ARCore is installed + this device is on Google's supported list. Always
  /// `false` from the native probe until R6.
  final bool arCoreAvailable;

  final RoomArCameraPermission cameraPermission;

  /// A conservative default used before/if the native probe fails: assume a
  /// GLES3 device with a camera whose permission we don't yet know — routing
  /// then lands on Tier 2, whose own permission handling takes over.
  static const RoomArDeviceCapabilities unknown = RoomArDeviceCapabilities(
    hasCamera: true,
    hasOpenGles3: true,
    markerEngineReady: true,
    arCoreAvailable: false,
    cameraPermission: RoomArCameraPermission.denied,
  );

  bool get cameraUsable =>
      hasCamera &&
      cameraPermission != RoomArCameraPermission.permanentlyDenied &&
      cameraPermission != RoomArCameraPermission.restricted;

  RoomArDeviceCapabilities copyWith({
    bool? hasCamera,
    bool? hasOpenGles3,
    bool? markerEngineReady,
    bool? arCoreAvailable,
    RoomArCameraPermission? cameraPermission,
  }) => RoomArDeviceCapabilities(
    hasCamera: hasCamera ?? this.hasCamera,
    hasOpenGles3: hasOpenGles3 ?? this.hasOpenGles3,
    markerEngineReady: markerEngineReady ?? this.markerEngineReady,
    arCoreAvailable: arCoreAvailable ?? this.arCoreAvailable,
    cameraPermission: cameraPermission ?? this.cameraPermission,
  );
}

/// The routing outcome plus a short machine reason (for logs / the tracker /
/// diagnostics — never shown raw to a customer).
class RoomArTierDecision {
  const RoomArTierDecision(this.tier, this.reason);
  final RoomArTier tier;
  final String reason;

  bool get isCameraAr =>
      tier == RoomArTier.tier2Marker || tier == RoomArTier.tier1Arcore;
  bool get isPreview => tier == RoomArTier.tier3Preview;
}

/// Deterministically pick the best **currently usable** Room-AR tier.
///
/// Order: Tier 1 (only if genuinely implemented + available) → Tier 2 (camera +
/// GLES3 + OpenCV + camera not blocked) → Tier 3 (GLES3) → unsupported.
/// Never returns a tier that cannot actually run right now.
RoomArTierDecision decideRoomArTier(RoomArDeviceCapabilities caps) {
  if (kTier1Implemented && caps.arCoreAvailable) {
    return const RoomArTierDecision(RoomArTier.tier1Arcore, 'arcore-available');
  }

  if (caps.hasOpenGles3 &&
      caps.hasCamera &&
      caps.markerEngineReady &&
      caps.cameraUsable) {
    return const RoomArTierDecision(RoomArTier.tier2Marker, 'marker-usable');
  }

  if (caps.hasOpenGles3) {
    final why = !caps.hasCamera
        ? 'no-camera'
        : !caps.markerEngineReady
        ? 'marker-engine-unavailable'
        : !caps.cameraUsable
        ? 'camera-permission-blocked'
        : 'camera-ar-unavailable';
    return RoomArTierDecision(RoomArTier.tier3Preview, why);
  }

  return const RoomArTierDecision(RoomArTier.unsupported, 'no-opengl-es-3');
}
