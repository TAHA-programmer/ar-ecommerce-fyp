import 'device_registration_backend.dart';

/// Test double for [DeviceRegistrationBackend]; records every call.
class MockDeviceRegistrationBackend implements DeviceRegistrationBackend {
  MockDeviceRegistrationBackend({
    this.registerResult = true,
    this.unregisterResult = true,
  });

  bool registerResult;
  bool unregisterResult;

  final List<({String token, String installId, String appVersion})>
  registerCalls = [];
  final List<String> unregisterCalls = [];

  @override
  Future<bool> register({
    required String token,
    required String installId,
    required String appVersion,
  }) async {
    registerCalls.add((
      token: token,
      installId: installId,
      appVersion: appVersion,
    ));
    return registerResult;
  }

  @override
  Future<bool> unregister({required String token}) async {
    unregisterCalls.add(token);
    return unregisterResult;
  }
}
