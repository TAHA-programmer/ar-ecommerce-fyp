package com.tahafayyaz.twin_ar.roomar

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * TWin AR — Phase 9.2 R6 Tier-1 markerless-ARCore native boundary.
 *
 * - PlatformView  `twin_ar/room_ar/arcore/view`    : real ARCore camera + plane/reticle GL layer + transparent Filament product overlay.
 * - MethodChannel `twin_ar/room_ar/arcore/methods` : setModel / place / reposition / rotate / reset / setActive.
 * - EventChannel  `twin_ar/room_ar/arcore/events`  : tracking / plane / anchor state each frame, plus terminal failure states.
 *
 * Independent of [RoomArMarkerPlugin] and [RoomArPreviewPlugin] — neither
 * physically-approved boundary is touched. Registered from
 * [com.tahafayyaz.twin_ar.MainActivity.configureFlutterEngine].
 */
object RoomArCorePlugin {
    const val CHANNEL_METHODS = "twin_ar/room_ar/arcore/methods"
    const val CHANNEL_EVENTS = "twin_ar/room_ar/arcore/events"
    const val VIEW_TYPE = "twin_ar/room_ar/arcore/view"

    @Volatile var activeView: RoomArCoreView? = null
    @Volatile private var eventSink: EventChannel.EventSink? = null

    fun emitFrame(state: RoomArCoreFrameState) {
        eventSink?.success(state.toMap())
    }

    /** A terminal, non-recoverable-without-a-retry state (missing permission,
     *  ARCore unavailable, install in progress, camera taken by another app).
     *  [state] is a short machine key the Dart ViewModel switches on — never
     *  shown raw to a customer. */
    fun emitTerminal(state: String, message: String) {
        eventSink?.success(
            mapOf(
                "tracking" to false,
                "trackingFailureReason" to "NONE",
                "planesFound" to false,
                "hasAnchor" to false,
                "anchorTracking" to false,
                "justPlaced" to false,
                "reticleVisible" to false,
                "terminalState" to state,
                "error" to message,
            ),
        )
    }

    fun register(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger

        engine.platformViewsController.registry
            .registerViewFactory(VIEW_TYPE, RoomArCoreViewFactory(messenger))

        MethodChannel(messenger, CHANNEL_METHODS).setMethodCallHandler { call, result ->
            val v = activeView
            when (call.method) {
                "setArMode" -> {
                    v?.setArMode(call.argument<String>("mode") ?: "chair")
                    result.success(null)
                }
                "setExternalModel" -> {
                    v?.setExternalModel(
                        call.argument<String>("mode") ?: "chair",
                        call.argument<String>("path"),
                    )
                    result.success(null)
                }
                "placeAt" -> {
                    v?.placeAt(
                        call.argument<Double>("fx") ?: 0.5,
                        call.argument<Double>("fy") ?: 0.5,
                    )
                    result.success(null)
                }
                "beginReposition" -> { v?.beginReposition(); result.success(null) }
                "repositionTo" -> {
                    v?.repositionTo(
                        call.argument<Double>("fx") ?: 0.5,
                        call.argument<Double>("fy") ?: 0.5,
                    )
                    result.success(null)
                }
                "endReposition" -> { v?.endReposition(); result.success(null) }
                "setYaw" -> {
                    v?.setYaw(call.argument<Double>("degrees") ?: 0.0)
                    result.success(null)
                }
                "resetPlacement" -> { v?.resetPlacement(); result.success(null) }
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
                }
                override fun onCancel(args: Any?) { eventSink = null }
            },
        )
    }
}
