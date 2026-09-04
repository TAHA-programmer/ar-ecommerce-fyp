import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'room_ar_capability.dart';

/// Reads the real device Room-AR capabilities: the native probe
/// ([RoomArCapabilitiesPlugin] over `twin_ar/room_ar/capabilities`) for
/// hardware / GLES / OpenCV / ARCore, plus `permission_handler` for the live
/// camera-permission state.
abstract class RoomArCapabilityService {
  Future<RoomArDeviceCapabilities> detect();
}

class DefaultRoomArCapabilityService implements RoomArCapabilityService {
  DefaultRoomArCapabilityService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('twin_ar/room_ar/capabilities');

  final MethodChannel _channel;

  @override
  Future<RoomArDeviceCapabilities> detect() async {
    final native = await _queryNative();
    final permission = await _cameraPermission();
    return RoomArDeviceCapabilities(
      hasCamera: native['hasCamera'] as bool? ?? true,
      hasOpenGles3: native['hasOpenGles3'] as bool? ?? true,
      markerEngineReady: native['markerEngineReady'] as bool? ?? true,
      arCoreAvailable: native['arCoreAvailable'] as bool? ?? false,
      cameraPermission: permission,
    );
  }

  Future<Map<String, dynamic>> _queryNative() async {
    try {
      final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('query');
      return m == null ? const {} : m.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      // No native probe (older engine / test host) → assume the conservative
      // "unknown" device so routing lands on Tier 2 and its own handling runs.
      return const {};
    }
  }

  Future<RoomArCameraPermission> _cameraPermission() async {
    try {
      final s = await Permission.camera.status;
      if (s.isGranted || s.isLimited) {
        return RoomArCameraPermission.granted;
      }
      if (s.isPermanentlyDenied) {
        return RoomArCameraPermission.permanentlyDenied;
      }
      if (s.isRestricted) return RoomArCameraPermission.restricted;
      return RoomArCameraPermission.denied;
    } catch (_) {
      return RoomArCameraPermission.denied;
    }
  }
}
