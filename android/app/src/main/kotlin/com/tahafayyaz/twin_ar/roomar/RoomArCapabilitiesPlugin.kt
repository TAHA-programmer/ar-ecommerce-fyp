package com.tahafayyaz.twin_ar.roomar

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * TWin AR — Phase 9.2 R8 device-capability probe for Room-AR tier routing.
 *
 * Reports only *facts about this device* — a rear camera, OpenGL ES 3.0, whether
 * the OpenCV marker engine loaded, and (R6) whether ARCore is genuinely usable.
 * The Flutter `RoomArCapabilityService` combines these with the runtime
 * camera-permission state and picks the best *currently usable* tier. This
 * plugin never launches anything.
 *
 * MethodChannel `twin_ar/room_ar/capabilities` — one method, `query`.
 *
 * Registered from [com.tahafayyaz.twin_ar.MainActivity.configureFlutterEngine].
 * Kept separate from [RoomArMarkerPlugin] so the physically-approved Tier-2
 * boundary is untouched.
 */
object RoomArCapabilitiesPlugin {
    const val CHANNEL = "twin_ar/room_ar/capabilities"

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "query" -> result.success(query(app))
                    else -> result.notImplemented()
                }
            }
    }

    private fun query(context: Context): Map<String, Any> {
        val pm = context.packageManager
        val hasCamera = pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)

        val glEsVersion = runCatching {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.deviceConfigurationInfo.reqGlEsVersion
        }.getOrDefault(0)
        val hasOpenGles3 = glEsVersion >= 0x30000 ||
            pm.hasSystemFeature(PackageManager.FEATURE_OPENGLES_EXTENSION_PACK)

        return mapOf(
            "hasCamera" to hasCamera,
            "glEsVersion" to glEsVersion,
            "hasOpenGles3" to hasOpenGles3,
            // Marker engine readiness — the same OpenCV load the Tier-2 plugin does.
            "markerEngineReady" to RoomArMarkerPlugin.openCvOk,
            // Phase 9.2 R6 — real runtime ARCore capability check, not a dead
            // flag. `ArCoreApk.checkAvailability()` is a real query against
            // Google Play Services for AR (cached after the first call); its
            // `isSupported` covers SUPPORTED_INSTALLED / SUPPORTED_APK_TOO_OLD /
            // SUPPORTED_NOT_INSTALLED — i.e. "this device could run ARCore",
            // even if the APK still needs installing/updating (the Tier-1
            // native view's own session-creation step handles that install
            // prompt when the customer actually starts AR). It is
            // deliberately `false` (not "supported") for the transient
            // `UNKNOWN_CHECKING` state on a device's very first-ever check —
            // never blocking this method-channel call to wait for Play
            // Services to resolve it — so a fresh session simply lands on
            // Tier 2/3 this one time; a retry or later launch reports
            // correctly once Play Services has cached the result. Devices
            // Google has explicitly marked incapable
            // (`UNSUPPORTED_DEVICE_NOT_CAPABLE`) always report `false`.
            "arCoreAvailable" to isArCoreAvailable(context),
        )
    }

    private fun isArCoreAvailable(context: Context): Boolean = runCatching {
        ArCoreApk.getInstance().checkAvailability(context).isSupported
    }.getOrDefault(false)
}
