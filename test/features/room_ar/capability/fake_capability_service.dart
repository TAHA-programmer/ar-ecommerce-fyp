import 'package:twin_ar/features/room_ar/capability/room_ar_capability.dart';
import 'package:twin_ar/features/room_ar/capability/room_ar_capability_service.dart';

/// A [RoomArCapabilityService] that returns a fixed capability snapshot.
class FakeRoomArCapabilityService implements RoomArCapabilityService {
  FakeRoomArCapabilityService([RoomArDeviceCapabilities? caps])
    : capabilities = caps ?? _infinix;

  RoomArDeviceCapabilities capabilities;
  int detectCalls = 0;

  /// The Infinix Hot 40: a camera + GLES3 + OpenCV, no ARCore, camera granted.
  static const RoomArDeviceCapabilities _infinix = RoomArDeviceCapabilities(
    hasCamera: true,
    hasOpenGles3: true,
    markerEngineReady: true,
    arCoreAvailable: false,
    cameraPermission: RoomArCameraPermission.granted,
  );

  static const infinix = _infinix;

  /// A GLES3 device whose camera is blocked → Tier 3.
  static const noCameraAr = RoomArDeviceCapabilities(
    hasCamera: true,
    hasOpenGles3: true,
    markerEngineReady: true,
    arCoreAvailable: false,
    cameraPermission: RoomArCameraPermission.permanentlyDenied,
  );

  /// No OpenGL ES 3.0 at all → unsupported.
  static const noGles = RoomArDeviceCapabilities(
    hasCamera: true,
    hasOpenGles3: false,
    markerEngineReady: false,
    arCoreAvailable: false,
    cameraPermission: RoomArCameraPermission.denied,
  );

  @override
  Future<RoomArDeviceCapabilities> detect() async {
    detectCalls++;
    return capabilities;
  }
}
