package com.tahafayyaz.twin_ar.roomar

import android.graphics.Bitmap
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.objdetect.Objdetect
import java.io.ByteArrayOutputStream

/**
 * TWin AR — Tier-2 Marker-AR native boundary (production port of the isolated
 * `_marker_ar_poc` engine; Phase 9.2 R5).
 *
 * All detection / solvePnP / One-Euro smoothing / camera-crop / model-transform
 * math is carried over from the physically-approved PoC **unchanged** — this
 * class only exposes it to Flutter over a clean, product-neutral channel.
 *
 * - PlatformView  `twin_ar/room_ar/marker/view`    : CameraX preview + OpenCV ArUco tracking + Filament overlay.
 * - MethodChannel `twin_ar/room_ar/marker/methods` : one-off calls (config, marker PNG, placement/calibration setters).
 * - EventChannel  `twin_ar/room_ar/marker/events`  : per-frame pose / honest track state / metrics.
 *
 * Marker contract (must match the printed A4 sheet and the detector):
 *   dictionary = DICT_5X5_100, id = 0, printed OUTER black square = 160.0 mm.
 *
 * Registered from [com.tahafayyaz.twin_ar.MainActivity.configureFlutterEngine].
 */
object RoomArMarkerPlugin {
    const val CHANNEL_METHODS = "twin_ar/room_ar/marker/methods"
    const val CHANNEL_EVENTS = "twin_ar/room_ar/marker/events"
    const val VIEW_TYPE = "twin_ar/room_ar/marker/view"

    const val DICT = Objdetect.DICT_5X5_100
    const val MARKER_ID = 0
    const val MARKER_MM = 160.0          // printed outer black-square side length

    // Canonical true-world product dimensions — W(X) H(Y) D(Z) metres — of the
    // four validated / physically-approved GLBs (tracker §6). Exposed to Flutter
    // via "config"; the Flutter side never guesses these.
    private val CHAIR_DIMS = listOf(0.70, 0.82, 0.72)
    private val TABLE_DIMS = listOf(0.90, 0.42, 0.90)
    private val LAMP_DIMS = listOf(0.20, 0.45, 0.20)
    private val SOFA_DIMS = listOf(2.65, 0.82, 1.65)

    @Volatile var eventSink: EventChannel.EventSink? = null
    @Volatile var openCvOk: Boolean = false

    /** The live AR view, so Flutter's app-lifecycle can pause/resume the camera. */
    @Volatile var activeView: RoomArMarkerView? = null

    fun register(engine: FlutterEngine) {
        if (!openCvOk) openCvOk = OpenCVLoader.initLocal()
        val messenger = engine.dartExecutor.binaryMessenger

        engine.platformViewsController.registry
            .registerViewFactory(VIEW_TYPE, RoomArMarkerViewFactory(messenger))

        MethodChannel(messenger, CHANNEL_METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "config" -> result.success(
                    mapOf(
                        "openCvOk" to openCvOk,
                        "openCvVersion" to OpenCVLoader.OPENCV_VERSION,
                        "dict" to "DICT_5X5_100",
                        "markerId" to MARKER_ID,
                        "markerMm" to MARKER_MM,
                        "chairDims" to CHAIR_DIMS,
                        "tableDims" to TABLE_DIMS,
                        "lampDims" to LAMP_DIMS,
                        "sofaDims" to SOFA_DIMS,
                    )
                )
                "setArMode" -> {
                    activeView?.setArMode(call.argument<String>("mode") ?: "chair")
                    result.success(null)
                }
                "setExternalModel" -> {
                    // Phase 9.2 R10 — path is a file RoomArModelService verified,
                    // or null to fall back to the bundled asset for that mode.
                    activeView?.setExternalModel(
                        call.argument<String>("mode") ?: "chair",
                        call.argument<String>("path"),
                    )
                    result.success(null)
                }
                "setObjectYaw" -> {
                    activeView?.setObjectYaw(call.argument<Double>("yaw") ?: 0.0)
                    result.success(null)
                }
                "setObjectOffset" -> {
                    activeView?.setObjectOffset(
                        call.argument<Double>("x") ?: 0.0,
                        call.argument<Double>("z") ?: 0.0,
                    )
                    result.success(null)
                }
                "resetPlacement" -> {
                    activeView?.resetPlacement()
                    result.success(null)
                }
                "setMarkerSizeMm" -> {
                    activeView?.setMarkerSizeMm(call.argument<Double>("mm") ?: MARKER_MM)
                    result.success(null)
                }
                "setScaleTrim" -> {
                    activeView?.setScaleTrim(call.argument<Double>("trim") ?: 1.0)
                    result.success(null)
                }
                "generateMarkerPng" -> {
                    val px = (call.argument<Int>("px")) ?: 1200
                    try {
                        result.success(generateMarkerPng(px))
                    } catch (e: Throwable) {
                        result.error("gen_failed", e.message, null)
                    }
                }
                "setActive" -> {
                    activeView?.setActive(call.argument<Boolean>("active") ?: true)
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
                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            }
        )
    }

    /** Renders the exact ArUco marker (dict/id) to a square PNG, no border padding. */
    private fun generateMarkerPng(px: Int): ByteArray {
        check(openCvOk) { "OpenCV not initialised" }
        val dict = Objdetect.getPredefinedDictionary(DICT)
        val m = Mat(px, px, CvType.CV_8UC1)
        Objdetect.generateImageMarker(dict, MARKER_ID, px, m, 1)
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(m, bmp)
        m.release()
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return out.toByteArray()
    }

    @Suppress("unused")
    fun b64(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
}
