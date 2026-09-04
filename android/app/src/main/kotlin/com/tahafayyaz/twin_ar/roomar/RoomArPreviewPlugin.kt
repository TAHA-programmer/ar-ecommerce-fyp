package com.tahafayyaz.twin_ar.roomar

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * TWin AR — Phase 9.2 R7 Tier-3 Interactive 3D Preview native boundary.
 *
 * - PlatformView  `twin_ar/room_ar/preview/view`    : transparent Filament orbit viewer, no camera.
 * - MethodChannel `twin_ar/room_ar/preview/methods` : setModel / orbit / pan / zoom / reset / setActive / config.
 * - EventChannel  `twin_ar/room_ar/preview/events`  : "loading" | "ready" | "failed" load states.
 *
 * Independent of [RoomArMarkerPlugin] — the physically-approved Tier-2 boundary
 * is not touched. Registered from
 * [com.tahafayyaz.twin_ar.MainActivity.configureFlutterEngine].
 */
object RoomArPreviewPlugin {
    const val CHANNEL_METHODS = "twin_ar/room_ar/preview/methods"
    const val CHANNEL_EVENTS = "twin_ar/room_ar/preview/events"
    const val VIEW_TYPE = "twin_ar/room_ar/preview/view"

    // Canonical true-world product dimensions — W(X) H(Y) D(Z) metres — of the
    // four validated GLBs, echoed to Flutter for the "actual size" caption.
    private val CHAIR_DIMS = listOf(0.70, 0.82, 0.72)
    private val TABLE_DIMS = listOf(0.90, 0.42, 0.90)
    private val LAMP_DIMS = listOf(0.20, 0.45, 0.20)
    private val SOFA_DIMS = listOf(2.65, 0.82, 1.65)

    @Volatile var activeView: RoomArPreviewView? = null
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var lastState: String = "loading"
    private val main = Handler(Looper.getMainLooper())

    fun emitLoadState(state: String) {
        lastState = state
        main.post { eventSink?.success(mapOf("state" to state)) }
    }

    fun register(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger

        engine.platformViewsController.registry
            .registerViewFactory(VIEW_TYPE, RoomArPreviewViewFactory(messenger))

        MethodChannel(messenger, CHANNEL_METHODS).setMethodCallHandler { call, result ->
            val v = activeView
            when (call.method) {
                "config" -> result.success(
                    mapOf(
                        "chairDims" to CHAIR_DIMS,
                        "tableDims" to TABLE_DIMS,
                        "lampDims" to LAMP_DIMS,
                        "sofaDims" to SOFA_DIMS,
                    )
                )
                "setModel" -> {
                    v?.setModel(
                        call.argument<String>("mode") ?: "chair",
                        call.argument<String>("path"),
                    )
                    result.success(null)
                }
                "orbit" -> {
                    v?.orbit(call.argument<Double>("dx") ?: 0.0, call.argument<Double>("dy") ?: 0.0)
                    result.success(null)
                }
                "pan" -> {
                    v?.pan(call.argument<Double>("dx") ?: 0.0, call.argument<Double>("dy") ?: 0.0)
                    result.success(null)
                }
                "zoom" -> {
                    v?.zoom(call.argument<Double>("scale") ?: 1.0)
                    result.success(null)
                }
                "reset" -> { v?.resetView(); result.success(null) }
                "setActive" -> {
                    v?.setActive(call.argument<Boolean>("active") ?: true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, CHANNEL_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    sink?.success(mapOf("state" to lastState))
                }
                override fun onCancel(args: Any?) { eventSink = null }
            }
        )
    }
}
