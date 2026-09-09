package com.tahafayyaz.twin_ar.roomar

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Size
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import io.flutter.plugin.platform.PlatformView
import org.opencv.calib3d.Calib3d
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfDouble
import org.opencv.core.MatOfPoint2f
import org.opencv.core.MatOfPoint3f
import org.opencv.core.Point3
import org.opencv.objdetect.ArucoDetector
import org.opencv.objdetect.DetectorParameters
import org.opencv.objdetect.Objdetect
import java.util.concurrent.Executors

/**
 * TWin AR Tier-2 Marker-AR PlatformView: CameraX preview + OpenCV ArUco pose
 * estimation + a transparent Filament model overlay, in one Android view.
 * Emits per-frame {track, fps, K, R, t, corners, ...} on
 * [RoomArMarkerPlugin.eventSink] for the Flutter [MarkerArViewModel].
 *
 * Ported verbatim from the physically-approved `_marker_ar_poc` engine — the
 * detector parameters, the FILL_CENTER pinhole model, the acquire/hold/lose
 * hysteresis and the pose feed are unchanged. Only class/method names and the
 * package were adapted for the production boundary.
 */
class RoomArMarkerView(
    private val context: Context,
    private val viewId: Int,
    initialMode: String = "chair",
) : PlatformView, LifecycleOwner {

    private val tag = "RoomArMarkerView"
    private val previewView = PreviewView(context).apply {
        // FILL_CENTER: the preview fills the whole view, centre-cropping the image.
        // The Filament layer uses a matching centre-cropped projection (RoomArModelRenderer),
        // so the two register exactly with no letterbox bars.
        scaleType = PreviewView.ScaleType.FILL_CENTER
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
    }
    // Filament model overlay — renders into a transparent TextureView layered
    // above the camera PreviewView (TextureView-over-TextureView composites reliably;
    // a separate transparent SurfaceView did not → "black camera" bug).
    private val modelRenderer: RoomArModelRenderer? =
        runCatching { RoomArModelRenderer(context, initialMode) }
            .onFailure { Log.e(tag, "RoomArModelRenderer init failed", it) }
            .getOrNull()

    private val root = FrameLayout(context).apply {
        addView(
            previewView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        modelRenderer?.let {
            addView(
                it.textureView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
        }
    }

    /** "chair" | "table" | "lamp" | "sofa" -> that product's Filament model. */
    fun setArMode(mode: String) { modelRenderer?.select(mode) }
    /** Phase 9.2 R10 — install a verified external GLB for [mode], or clear it
     *  ([path] = null) to fall back to the bundled asset. [path] must be a file
     *  RoomArModelService has already fully verified. */
    fun setExternalModel(mode: String, path: String?) {
        modelRenderer?.setExternalModel(mode, path)
    }
    fun setObjectYaw(y: Double) { modelRenderer?.yaw = y }
    /** drag: metres along the marker plane (+X right, +Z forward on the sheet).
     *  Clamped to a 0.6 m radius around the marker so ordinary dragging can't send
     *  the model outside the visible/renderable area. */
    fun setObjectOffset(x: Double, z: Double) {
        modelRenderer?.let {
            val maxR = 0.6
            val d = kotlin.math.hypot(x, z)
            val k = if (d > maxR) maxR / d else 1.0
            it.offsetX = x * k
            it.offsetZ = z * k
        }
    }
    fun resetPlacement() { modelRenderer?.resetPlacement() }
    fun setScaleTrim(trim: Double) { recomputeScale(trimOverride = trim) }
    fun setMarkerSizeMm(mm: Double) {
        markerSizeMm = if (mm.isFinite() && mm in 20.0..600.0) mm else 160.0
        rebuildObjPoints()
        recomputeScale()
    }

    private var scaleTrim = 1.0
    private fun recomputeScale(trimOverride: Double? = null) {
        trimOverride?.let { scaleTrim = if (it.isFinite() && it in 0.5..2.0) it else 1.0 }
        // solvePnP already uses the true markerSizeMm, so the pose is metric →
        // chair renders at authored size with multiplier = scaleTrim only.
        modelRenderer?.scaleMultiplier = scaleTrim
    }

    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry

    private val main = Handler(Looper.getMainLooper())
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private var cameraProvider: ProcessCameraProvider? = null
    private var disposed = false

    // ArUco — near-default parameters. Round 2's very permissive settings
    // (minMarkerPerimeterRate 0.018, wide sweeps) produced hundreds of candidate
    // quads on a textured rug → ~109 ms/frame and unreliable locks. Range comes
    // from the ROI tracking + the digital-zoom reacquire, not permissiveness.
    private val dictionary = Objdetect.getPredefinedDictionary(RoomArMarkerPlugin.DICT)
    private val detector = ArucoDetector(dictionary, DetectorParameters().apply {
        set_cornerRefinementMethod(Objdetect.CORNER_REFINE_SUBPIX)
        set_cornerRefinementWinSize(4)
        set_cornerRefinementMinAccuracy(0.05)
        set_minMarkerPerimeterRate(0.03)            // OpenCV default
        set_maxErroneousBitsInBorderRate(0.35)      // OpenCV default
        set_errorCorrectionRate(0.6)                // OpenCV default
        set_polygonalApproxAccuracyRate(0.03)       // OpenCV default
    })
    // marker side length (px) below which the pose is considered untrustworthy.
    private val minReliableMarkerPx = 14.0
    // acquire / hold / lose:
    private var hitStreak = 0
    private var missStreak = 0
    private var stableFoundPrev = false
    private val acquireFrames = 2
    private var lastGoodPoseNs = 0L
    private val trackGraceNs = 300_000_000L   // still "TRACKING" if a valid frame was this recent
    private val holdNs = 1_200_000_000L       // freeze last pose up to this long -> "HOLDING"
    private var frameIdx = 0L
    private var avgDetMs = 0.0
    // ROI tracking: last marker bounding box (full-frame px) to search inside next frame
    private var roiValid = false
    private var roiX0 = 0.0; private var roiY0 = 0.0; private var roiX1 = 0.0; private var roiY1 = 0.0
    @Volatile private var markerSizeMm = RoomArMarkerPlugin.MARKER_MM
    private var objPoints = makeObjPoints(markerSizeMm)
    private fun makeObjPoints(mm: Double): MatOfPoint3f {
        val h = (mm / 1000.0) / 2.0
        return MatOfPoint3f(
            Point3(-h, h, 0.0), Point3(h, h, 0.0), Point3(h, -h, 0.0), Point3(-h, -h, 0.0),
        )
    }
    @Synchronized private fun rebuildObjPoints() {
        val old = objPoints
        objPoints = makeObjPoints(markerSizeMm)
        runCatching { old.release() }
    }

    // camera intrinsics (filled once the camera is bound)
    private var focalMm = 0f
    private var sensorWmm = 0f
    private var sensorHmm = 0f

    // fps
    private val frameTimes = ArrayDeque<Long>()

    private var cameraStarted = false

    init {
        registry.currentState = Lifecycle.State.CREATED
        RoomArMarkerPlugin.activeView = this
        modelRenderer?.start()
        if (!RoomArMarkerPlugin.openCvOk) {
            emitError("OpenCV failed to initialise")
        } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            emitError("Camera permission not granted")
        } else {
            startCamera()
        }
    }

    /** Driven by Flutter's app lifecycle (see MarkerArViewModel). CameraX
     *  observes [registry]: RESUMED reopens + rebinds, CREATED closes the camera. */
    fun setActive(active: Boolean) {
        if (disposed) return
        if (active) {
            registry.currentState = Lifecycle.State.RESUMED
            modelRenderer?.start()
            if (!cameraStarted &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED
            ) startCamera()
        } else {
            registry.currentState = Lifecycle.State.CREATED
            modelRenderer?.stop()
        }
    }

    private fun startCamera() {
        cameraStarted = true
        registry.currentState = Lifecycle.State.RESUMED
        // Defer until the PreviewView has been laid out so previewView.viewPort
        // is available (aligns Preview + Analysis crop rects with the display).
        previewView.post { bindCamera() }
    }

    private fun bindCamera() {
        if (disposed) return
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            try {
                val provider = future.get()
                cameraProvider = provider

                // Same aspect ratio on both use cases so Preview and Analysis
                // share a field of view; a ViewPort (below) then aligns their
                // crop rects so the overlay registers with the preview.
                // Both use cases at 1280x960 (4:3, a shared ViewPort aligns their
                // crop rects). 4:3 = the phone's native sensor shape, so it's the
                // full frame (no 16:9 crop) → ~33% more pixels on a far marker AND
                // a cleaner pinhole model. 1080p was tried and rejected (>1.5 s /
                // frame on this Helio-G88 CPU); 960p + no frame-skip + the always-on
                // digital-zoom retry is the balance point.
                val resSel = ResolutionSelector.Builder()
                    .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
                    .setResolutionStrategy(
                        ResolutionStrategy(Size(1280, 960),
                            ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)
                    ).build()
                val preview = Preview.Builder()
                    .setResolutionSelector(resSel)
                    .build()
                    .also { it.setSurfaceProvider(previewView.surfaceProvider) }
                val analysis = ImageAnalysis.Builder()
                    .setResolutionSelector(resSel)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                    .build()
                analysis.setAnalyzer(analysisExecutor) { proxy -> analyze(proxy) }

                provider.unbindAll()
                val groupBuilder = UseCaseGroup.Builder()
                    .addUseCase(preview)
                    .addUseCase(analysis)
                previewView.viewPort?.let { groupBuilder.setViewPort(it) }
                val camera = provider.bindToLifecycle(
                    this, CameraSelector.DEFAULT_BACK_CAMERA, groupBuilder.build()
                )
                readIntrinsics(camera.cameraInfo)
            } catch (e: Throwable) {
                Log.e(tag, "camera bind failed", e)
                emitError("Camera failed to start: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    @OptIn(ExperimentalCamera2Interop::class)
    private fun readIntrinsics(info: androidx.camera.core.CameraInfo) {
        try {
            val c2 = Camera2CameraInfo.from(info)
            val focals = c2.getCameraCharacteristic(
                CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS
            )
            val physical = c2.getCameraCharacteristic(
                CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE
            )
            focalMm = focals?.firstOrNull() ?: 0f
            sensorWmm = physical?.width ?: 0f
            sensorHmm = physical?.height ?: 0f
            Log.i(tag, "intrinsics: focal=$focalMm mm sensor=${sensorWmm}x$sensorHmm mm")
        } catch (e: Throwable) {
            Log.w(tag, "could not read intrinsics", e)
        }
    }

    private fun analyze(proxy: ImageProxy) {
        val t0 = System.nanoTime()
        var gray: Mat? = null
        try {
            gray = yPlaneToGray(proxy)
            val rot = proxy.imageInfo.rotationDegrees
            gray = rotate(gray, rot)
            val w = gray.cols()
            val h = gray.rows()

            // Pinhole model for the upright analysis image. The 4:3 analysis stream
            // is the phone's native (uncropped) sensor shape, so with square pixels:
            //   fx == fy == focal_mm / sensor_long_mm * image_long_px
            // principal point = image centre.
            val fx: Double
            val fy: Double
            if (focalMm > 0f && sensorWmm > 0f && sensorHmm > 0f) {
                val sensorLong = maxOf(sensorWmm, sensorHmm).toDouble()
                val imgLong = maxOf(w, h).toDouble()
                val f = focalMm.toDouble() / sensorLong * imgLong
                fx = f; fy = f
            } else {
                // fallback: assume ~62° FOV on the long axis
                val imgLong = maxOf(w, h).toDouble()
                val f = (imgLong / 2.0) / Math.tan(Math.toRadians(62.0 / 2.0))
                fx = f; fy = f
            }
            val cx = w / 2.0
            val cy = h / 2.0

            val op = synchronized(this) { objPoints }   // stable ref across a rebuild
            frameIdx++

            // ---- adaptive detection ----------------------------------------
            //  * tracking  -> search only a small ROI at full res (fast + accurate)
            //  * fallback  -> full frame at 0.65x (fast enough for acquisition)
            //  * searching -> + a periodic 2x centre-crop reacquire (extra range)
            var quad: FloatArray? = null
            var pass = "full"
            if (roiValid) {   // last position known -> try the small ROI first (fast + accurate)
                val r = trackingRoi(w, h)
                quad = detectMarkerQuad(gray, r[0], r[1], r[2], r[3], 1.0)
                if (quad != null) pass = "roi"
            }
            if (quad == null) {   // full-frame acquisition (downsampled for speed)
                quad = detectMarkerQuad(gray, 0, 0, w, h, 0.65)
                if (quad != null) pass = "full"
            }
            if (quad == null && !stableFoundPrev && frameIdx % 3L == 0L) {
                quad = detectMarkerQuad(gray, w / 4, h / 4, w / 2, h / 2, 2.0)
                if (quad != null) pass = "zoom"
            }
            // if the fast/coarse pass found it, refine once at full res in a tight ROI
            if (quad != null && pass != "roi") {
                setRoiFromQuad(quad!!)
                val r = trackingRoi(w, h)
                val refined = detectMarkerQuad(gray, r[0], r[1], r[2], r[3], 1.0)
                if (refined != null) quad = refined
            }

            var markerSidePx = 0.0
            if (quad != null) {
                var per = 0.0
                for (k in 0 until 4) {
                    val a = k * 2; val b = ((k + 1) % 4) * 2
                    per += Math.hypot(quad[b] - quad[a].toDouble(), quad[b + 1] - quad[a + 1].toDouble())
                }
                markerSidePx = per / 4.0
            }
            val tooSmall = quad != null && markerSidePx < minReliableMarkerPx

            var rArr: DoubleArray? = null
            var tArr: DoubleArray? = null
            var cornerArr: DoubleArray? = null
            if (quad != null && !tooSmall) {
                val pts = ArrayList<org.opencv.core.Point>(4)
                for (k in 0 until 4) pts.add(org.opencv.core.Point(quad[k * 2].toDouble(), quad[k * 2 + 1].toDouble()))
                val imgPoints = MatOfPoint2f(*pts.toTypedArray())
                val K = Mat(3, 3, CvType.CV_64F)
                K.put(0, 0, fx, 0.0, cx, 0.0, fy, cy, 0.0, 0.0, 1.0)
                val dist = MatOfDouble(0.0, 0.0, 0.0, 0.0, 0.0)
                val rvec = Mat(); val tvec = Mat()
                val ok = Calib3d.solvePnP(op, imgPoints, K, dist, rvec, tvec, false, Calib3d.SOLVEPNP_IPPE_SQUARE)
                if (ok) {
                    val R = Mat()
                    Calib3d.Rodrigues(rvec, R)
                    rArr = DoubleArray(9)
                    for (r in 0 until 3) for (cc in 0 until 3) rArr[r * 3 + cc] = R.get(r, cc)[0]
                    tArr = doubleArrayOf(tvec.get(0, 0)[0], tvec.get(1, 0)[0], tvec.get(2, 0)[0])
                    cornerArr = DoubleArray(8) { quad[it].toDouble() }
                    R.release()
                }
                K.release(); dist.release(); rvec.release(); tvec.release(); imgPoints.release()
            }

            val rawHit = rArr != null
            if (rawHit) {
                hitStreak++; missStreak = 0
                setRoiFromQuad(quad!!)
            } else {
                missStreak++; hitStreak = 0
                if (missStreak > 10) roiValid = false   // stop ROI-guessing after sustained loss
            }

            val now = System.nanoTime()
            if (rawHit) lastGoodPoseNs = now
            val sinceGood = now - lastGoodPoseNs

            // acquire needs a couple of consecutive hits; once acquired it stays
            // "found" until holdNs has fully elapsed with no good pose.
            val stableFound = when {
                rawHit && (stableFoundPrev || hitStreak >= acquireFrames) -> true
                !rawHit && sinceGood >= holdNs -> false
                else -> stableFoundPrev
            }
            stableFoundPrev = stableFound

            // ---- truthful status -----------------------------------------
            //  TRACKING : genuine detection this frame (or within a short grace)
            //  HOLDING  : no detection, last pose frozen, still inside holdNs
            //  TOOFAR   : a marker is visible but too few px to trust, and no held pose
            //  SEARCHING: nothing, past the hold
            val track = when {
                rawHit || sinceGood < trackGraceNs -> "tracking"
                sinceGood < holdNs -> "holding"
                tooSmall -> "toofar"
                else -> "searching"
            }
            val showModel = track == "tracking" || track == "holding"

            trackFps(now)
            val detMs = (now - t0) / 1_000_000.0
            avgDetMs = if (avgDetMs == 0.0) detMs else avgDetMs * 0.85 + detMs * 0.15

            val payload = HashMap<String, Any>()
            payload["track"] = track
            payload["state"] = if (showModel) "detected" else "searching"   // legacy field
            payload["fps"] = currentFps()
            payload["detMs"] = detMs
            payload["pass"] = pass
            payload["heldMs"] = if (rawHit) 0.0 else sinceGood / 1_000_000.0
            payload["imgW"] = w
            payload["imgH"] = h
            payload["K"] = doubleArrayOf(fx, fy, cx, cy).toList()
            payload["focalMm"] = focalMm.toDouble()
            payload["markerSidePx"] = markerSidePx
            payload["scalePass"] = if (pass == "zoom") 2 else 1
            if (rawHit) {
                payload["R"] = rArr!!.toList()
                payload["t"] = tArr!!.toList()
                payload["corners"] = cornerArr!!.toList()
                payload["distM"] = Math.sqrt(tArr[0] * tArr[0] + tArr[1] * tArr[1] + tArr[2] * tArr[2])
            }
            modelRenderer?.updatePose(rArr, tArr, fx, fy, w, h, showModel)
            payload["markerSizeMm"] = markerSizeMm
            emit(payload)
        } catch (e: Throwable) {
            Log.e(tag, "analyze error", e)
        } finally {
            gray?.release()
            proxy.close()
        }
    }

    /**
     * Detect marker id 0 inside the given ROI of [gray] and return its 4 corners
     * as 8 floats in FULL-FRAME px, or null. [scale] > 1 up-samples the ROI first
     * (a "controlled digital zoom" — re-uses captured pixels, no fabricated data;
     * corners are mapped back to full-frame coords).
     */
    private fun detectMarkerQuad(
        gray: Mat, rx: Int, ry: Int, rw: Int, rh: Int, scale: Double,
    ): FloatArray? {
        val x = rx.coerceIn(0, gray.cols() - 2)
        val y = ry.coerceIn(0, gray.rows() - 2)
        val w = rw.coerceIn(2, gray.cols() - x)
        val h = rh.coerceIn(2, gray.rows() - y)
        var roiMat: Mat? = null
        var scaled: Mat? = null
        try {
            val full = x == 0 && y == 0 && w == gray.cols() && h == gray.rows()
            var work = if (full) gray else Mat(gray, org.opencv.core.Rect(x, y, w, h)).also { roiMat = it }
            if (scale != 1.0) {
                // scale < 1 = downsample (faster full-frame search); > 1 = upsample
                // (digital-zoom reacquire). INTER_AREA is best for shrinking.
                scaled = Mat()
                val interp = if (scale < 1.0) org.opencv.imgproc.Imgproc.INTER_AREA
                             else org.opencv.imgproc.Imgproc.INTER_LINEAR
                org.opencv.imgproc.Imgproc.resize(
                    work, scaled, org.opencv.core.Size(w * scale, h * scale), 0.0, 0.0, interp,
                )
                work = scaled!!
            }
            val corners = ArrayList<Mat>()
            val ids = Mat()
            detector.detectMarkers(work, corners, ids)
            var out: FloatArray? = null
            if (!ids.empty()) {
                for (i in 0 until ids.rows()) {
                    if (ids.get(i, 0)[0].toInt() != RoomArMarkerPlugin.MARKER_ID) continue
                    val buf = FloatArray(8)
                    corners[i].get(0, 0, buf)
                    for (k in 0 until 4) {
                        buf[k * 2] = (buf[k * 2] / scale + x).toFloat()
                        buf[k * 2 + 1] = (buf[k * 2 + 1] / scale + y).toFloat()
                    }
                    out = buf
                    break
                }
            }
            corners.forEach { it.release() }
            ids.release()
            return out
        } finally {
            roiMat?.release(); scaled?.release()
        }
    }

    /** grow the last-known marker bbox by a margin and clamp — the ROI to search. */
    private fun trackingRoi(w: Int, h: Int): IntArray {
        val bw = roiX1 - roiX0; val bh = roiY1 - roiY0
        val mx = bw * 1.1 + 12.0; val my = bh * 1.1 + 12.0
        val x0 = (roiX0 - mx).coerceIn(0.0, w - 2.0)
        val y0 = (roiY0 - my).coerceIn(0.0, h - 2.0)
        val x1 = (roiX1 + mx).coerceIn(x0 + 2.0, w.toDouble())
        val y1 = (roiY1 + my).coerceIn(y0 + 2.0, h.toDouble())
        return intArrayOf(x0.toInt(), y0.toInt(), (x1 - x0).toInt(), (y1 - y0).toInt())
    }

    private fun setRoiFromQuad(q: FloatArray) {
        var x0 = Float.MAX_VALUE; var y0 = Float.MAX_VALUE; var x1 = -Float.MAX_VALUE; var y1 = -Float.MAX_VALUE
        for (k in 0 until 4) {
            x0 = minOf(x0, q[k * 2]); x1 = maxOf(x1, q[k * 2])
            y0 = minOf(y0, q[k * 2 + 1]); y1 = maxOf(y1, q[k * 2 + 1])
        }
        roiX0 = x0.toDouble(); roiY0 = y0.toDouble(); roiX1 = x1.toDouble(); roiY1 = y1.toDouble()
        roiValid = true
    }

    private fun yPlaneToGray(proxy: ImageProxy): Mat {
        val plane = proxy.planes[0]
        val buf = plane.buffer
        val rowStride = plane.rowStride
        val w = proxy.width
        val h = proxy.height
        val m = Mat(h, w, CvType.CV_8UC1)
        if (rowStride == w) {
            val bytes = ByteArray(buf.remaining()); buf.get(bytes); m.put(0, 0, bytes)
        } else {
            val row = ByteArray(w)
            for (r in 0 until h) {
                buf.position(r * rowStride)
                buf.get(row, 0, w)
                m.put(r, 0, row)
            }
        }
        return m
    }

    private fun rotate(src: Mat, deg: Int): Mat {
        if (deg == 0) return src
        val dst = Mat()
        val code = when (deg) {
            90 -> Core.ROTATE_90_CLOCKWISE
            180 -> Core.ROTATE_180
            270 -> Core.ROTATE_90_COUNTERCLOCKWISE
            else -> { return src }
        }
        Core.rotate(src, dst, code)
        src.release()
        return dst
    }

    private fun trackFps(nowNs: Long) {
        frameTimes.addLast(nowNs)
        while (frameTimes.size > 30) frameTimes.removeFirst()
        while (frameTimes.isNotEmpty() && nowNs - frameTimes.first() > 2_000_000_000L) frameTimes.removeFirst()
    }
    private fun currentFps(): Double {
        if (frameTimes.size < 2) return 0.0
        val span = (frameTimes.last() - frameTimes.first()) / 1_000_000_000.0
        return if (span > 0) (frameTimes.size - 1) / span else 0.0
    }

    private fun emit(map: Map<String, Any>) {
        if (disposed) return
        main.post { RoomArMarkerPlugin.eventSink?.success(map) }
    }
    private fun emitError(msg: String) {
        emit(mapOf("state" to "error", "message" to msg))
    }

    override fun getView(): View = root

    override fun dispose() {
        disposed = true
        if (RoomArMarkerPlugin.activeView === this) RoomArMarkerPlugin.activeView = null
        try { cameraProvider?.unbindAll() } catch (_: Throwable) {}
        registry.currentState = Lifecycle.State.DESTROYED
        analysisExecutor.shutdown()
        try { modelRenderer?.destroy() } catch (e: Throwable) { Log.w(tag, "renderer destroy", e) }
        try { objPoints.release() } catch (_: Throwable) {}
    }
}
