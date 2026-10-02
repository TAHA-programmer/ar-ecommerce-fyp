import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/stripe_config.dart';
import '../notification_constants.dart';
import 'device_registration_backend.dart';

/// Real [DeviceRegistrationBackend] over Cloud Functions (`us-central1`).
/// The FirebaseFunctions instance is resolved lazily (same reasoning as
/// `StripeCheckoutPaymentService`). An undeployed function or an offline
/// device simply returns `false`; the caller retries on a later launch/login.
/// Only the exception TYPE is ever logged - never a token.
class CallableDeviceRegistrationBackend implements DeviceRegistrationBackend {
  CallableDeviceRegistrationBackend({FirebaseFunctions? functions})
    : _injected = functions;

  final FirebaseFunctions? _injected;

  FirebaseFunctions get _functions =>
      _injected ??
      FirebaseFunctions.instanceFor(region: StripeConfig.functionsRegion);

  @override
  Future<bool> register({
    required String token,
    required String installId,
    required String appVersion,
  }) async {
    try {
      await _functions
          .httpsCallable(NotificationConstants.registerDeviceCallable)
          .call<Object?>({
            'token': token,
            'platform': NotificationConstants.platform,
            'appVersion': appVersion,
            'installId': installId,
          })
          .timeout(NotificationConstants.registerTimeout);
      return true;
    } catch (e) {
      debugPrint('registerDevice failed: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<bool> unregister({required String token}) async {
    try {
      await _functions
          .httpsCallable(NotificationConstants.unregisterDeviceCallable)
          .call<Object?>({'token': token})
          .timeout(NotificationConstants.unregisterTimeout);
      return true;
    } catch (e) {
      debugPrint('unregisterDevice failed: ${e.runtimeType}');
      return false;
    }
  }
}
