package com.tahafayyaz.twin_ar.roomar

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * TWin AR — Phase 9.2 R8 device-capability probe for Room-AR tier routing.
 *
 * Reports only *facts about this device* — a rear camera, OpenGL ES 3.0, whether
 * the OpenCV marker engine loaded — plus an explicit `arCoreAvailable = false`
 * (Tier-1 / R6 is not implemented in this build). The Flutter
 * `RoomArCapabilityService` combines these with the runtime camera-permission
 * state and picks the best *currently usable* tier. This plugin never launches
 * anything.
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
            // Tier 1 (ARCore markerless) is NOT implemented in this build (R6).
            // Never report it as available, so routing can never pick a
            // nonexistent experience.
            "arCoreAvailable" to false,
        )
    }
}
