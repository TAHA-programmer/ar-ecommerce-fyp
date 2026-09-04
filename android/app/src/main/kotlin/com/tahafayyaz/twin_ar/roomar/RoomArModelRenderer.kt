package com.tahafayyaz.twin_ar.roomar

import android.content.Context
import android.view.Choreographer
import android.view.Surface
import android.view.TextureView
import com.google.android.filament.Camera
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.SwapChain
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.android.UiHelper
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import com.google.android.filament.utils.Utils
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * TWin AR Tier-2 Marker-AR Filament overlay (production port of the PoC
 * `ChairRenderer`; math unchanged).
 *
 * Renders one validated glTF product model (chair / coffee table / lamp / sofa)
 * anchored to the OpenCV ArUco marker pose, into a **TextureView** (not a
 * SurfaceView). A TextureView composites
 * through the hardware-accelerated view pipeline, so a transparent Filament
 * render blends correctly over the CameraX preview beneath it — unlike a
 * separate transparent SurfaceView layer, whose alpha / z-order is unreliable
 * across devices (that was the "black camera" bug).
 *
 * Marker frame (matches the solvePnP objPoints):
 *   origin = marker centre, +X right, +Y up in the printed plane, +Z out of the sheet.
 * OpenCV camera frame: +X right, +Y down, +Z forward. GL/Filament eye: +X right,
 * +Y up, +Z back. Conversion applied per-frame: flip Y and Z (diag(1,-1,-1)).
 *
 * Real metric scale: every GLB is authored in metres and floor-centred, +Y up,
 * seating/front face −Z (`SCALE_CONTRACT.md`). A calibration multiplier
 * ([scaleMultiplier]) scales the whole model; marker size is handled upstream by
 * re-solving solvePnP so the pose itself stays metric.
 */
class RoomArModelRenderer(context: Context) {

    companion object {
        init { Utils.init() }   // loads libfilament-jni / gltfio-jni
        private const val CHAIR_ASSET = "luna_accent_chair.glb"
        private const val TABLE_ASSET = "round_wood_coffee_table.glb"
        private const val LAMP_ASSET = "modern_table_lamp.glb"
        private const val SOFA_ASSET = "luna_right_chaise_sofa.glb"
        private const val SHADOW_ASSET = "shadow_blob.glb"
        val CHAIR_DIMS = floatArrayOf(0.70f, 0.82f, 0.72f)
        val TABLE_DIMS = floatArrayOf(0.90f, 0.42f, 0.90f)   // W(X) H(Y) D(Z) metres
        val LAMP_DIMS = floatArrayOf(0.20f, 0.45f, 0.20f)    // Modern Table Lamp
        val SOFA_DIMS = floatArrayOf(2.65f, 0.82f, 1.65f)    // Luna Right-Chaise Sectional Sofa

        // Sofa contact shadow — the footprint is a large L, not a disc. Two
        // overlapping restrained soft ellipses (the radius-1 `shadow_blob` disc
        // scaled per-axis): one under the main run, one under the right chaise.
        // Values are model-local metres (X = long axis, Z = chaise projection),
        // inset ~5 cm from the body so the shadow never spills past the sofa.
        //                       centreX  centreZ  halfX  halfZ
        val SOFA_SHADOW_MAIN = doubleArrayOf(0.05, 0.20, 1.18, 0.55)
        val SOFA_SHADOW_CHAISE = doubleArrayOf(-0.82, -0.05, 0.52, 0.74)
    }

    val textureView = TextureView(context).apply {
        isOpaque = false   // transparent where Filament renders nothing
    }

    private val engine = Engine.create()
    private val renderer = engine.createRenderer().apply {
        clearOptions = Renderer.ClearOptions().apply {
            clear = true
            clearColor = floatArrayOf(0f, 0f, 0f, 0f)   // transparent background
        }
    }
    private val scene = engine.createScene()
    private val cameraEntity = EntityManager.get().create()
    private val camera = engine.createCamera(cameraEntity)
    private val view = engine.createView().apply {
        this.scene = this@RoomArModelRenderer.scene
        this.camera = this@RoomArModelRenderer.camera
        blendMode = View.BlendMode.TRANSLUCENT
        // Post-processing ON: verified to output correct alpha into the TextureView
        // on the Infinix (the camera showed through). It also gives FXAA. The ~33 fps
        // render cap below keeps its cost off the SoC / heat budget.
        isPostProcessingEnabled = true
    }

    private val materialProvider = UbershaderProvider(engine)
    private val assetLoader = AssetLoader(engine, materialProvider, EntityManager.get())
    private val resourceLoader = ResourceLoader(engine)

    private val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK).apply {
        isOpaque = false
    }

    private var swapChain: SwapChain? = null
    private var chairAsset: FilamentAsset? = null
    private var tableAsset: FilamentAsset? = null
    private var lampAsset: FilamentAsset? = null
    private var sofaAsset: FilamentAsset? = null

    // Phase 9.2 R10 — verified external GLBs delivered from Firebase Storage
    // (RoomArModelService). Keyed by product mode ("chair"/"table"/"lamp"/
    // "sofa"). When present, the external asset REPLACES the bundled one for
    // that slot; a null entry (or absent key) means "use the bundled asset".
    // Only a path the Flutter side already downloaded, hashed and bounding-box
    // checked is ever passed here — this class never opens an arbitrary path.
    private val externalAssets = HashMap<String, FilamentAsset?>()

    private var shadowAsset: FilamentAsset? = null
    private var shadowAsset2: FilamentAsset? = null   // 2nd soft quad — sofa L footprint only
    private var current: FilamentAsset? = null

    // real surface pixel size, from UiHelper.onResized — the ONLY source of truth
    // for the viewport (never read back view.viewport, which we mutate each frame).
    @Volatile private var surfaceW = 0
    @Volatile private var surfaceH = 0

    // footprint radius (metres) of the current object, for sizing the contact shadow
    @Volatile private var footRadius = 0.42f

    private val appContext = context.applicationContext
    private var sunEntity = 0
    private var fillEntity = 0
    private var indirect: IndirectLight? = null

    // pose state (marker -> OpenCV camera)
    @Volatile private var haverPose = false
    @Volatile private var visible = false
    private var rCV = DoubleArray(9)
    private var tCV = DoubleArray(3)
    private var fx = 0.0; private var fy = 0.0
    private var imgW = 0; private var imgH = 0

    // user / calibration + manipulation controls
    @Volatile var yaw = 0.0
    @Volatile var scaleMultiplier = 1.0
    @Volatile var offsetX = 0.0   // metres along the marker plane +X (right)
    @Volatile var offsetZ = 0.0   // metres along the marker plane +Y (forward on the sheet)
    @Volatile private var mode = "chair"

    private val smoother = PoseSmoother()
    private var choreographer: Choreographer? = null
    private var running = false

    // cap the Filament render loop at ~33 fps — the ArUco pose feed is ~15-25 fps
    // and rendering faster just burns the shared SoC / battery / heat budget.
    private var lastRenderNs = 0L
    private val minFramePeriodNs = 30_000_000L
    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!running) return
            choreographer?.postFrameCallback(this)
            if (frameTimeNanos - lastRenderNs < minFramePeriodNs) return
            lastRenderNs = frameTimeNanos
            renderFrame(frameTimeNanos)
        }
    }

    init {
        uiHelper.setRenderCallback(object : UiHelper.RendererCallback {
            override fun onNativeWindowChanged(surface: Surface) {
                swapChain?.let { engine.destroySwapChain(it) }
                swapChain = engine.createSwapChain(surface, uiHelper.swapChainFlags)
            }
            override fun onDetachedFromSurface() {
                swapChain?.let { engine.destroySwapChain(it); engine.flushAndWait(); swapChain = null }
            }
            override fun onResized(w: Int, h: Int) {
                surfaceW = w; surfaceH = h
                view.viewport = Viewport(0, 0, w, h)
            }
        })
        uiHelper.attachTo(textureView)
        setupLighting()
        loadAssets()
        select(mode)
    }

    // ---- lighting: flat ambient IBL + key + fill directional --------------
    private fun setupLighting() {
        indirect = IndirectLight.Builder()
            .irradiance(1, floatArrayOf(0.72f, 0.72f, 0.75f))
            .intensity(30_000f)
            .build(engine)
        scene.indirectLight = indirect

        sunEntity = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 0.98f, 0.95f).intensity(75_000f)
            .direction(0.35f, -0.9f, -0.25f).castShadows(false)
            .build(engine, sunEntity)
        scene.addEntity(sunEntity)

        fillEntity = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.9f, 0.93f, 1.0f).intensity(24_000f)
            .direction(-0.4f, -0.2f, 0.6f).castShadows(false)
            .build(engine, fillEntity)
        scene.addEntity(fillEntity)
    }

    private fun readAsset(name: String): ByteBuffer {
        val bytes = appContext.assets.open(name).use { it.readBytes() }
        return ByteBuffer.allocateDirect(bytes.size).apply { put(bytes); rewind() }
    }

    private fun loadAssets() {
        chairAsset = assetLoader.createAsset(readAsset(CHAIR_ASSET))?.also {
            resourceLoader.loadResources(it); it.releaseSourceData()
        }
        tableAsset = runCatching { assetLoader.createAsset(readAsset(TABLE_ASSET)) }
            .onFailure { android.util.Log.e("RoomArModelRenderer", "table asset load failed", it) }
            .getOrNull()?.also {
                resourceLoader.loadResources(it); it.releaseSourceData()
            }
        lampAsset = runCatching { assetLoader.createAsset(readAsset(LAMP_ASSET)) }
            .onFailure { android.util.Log.e("RoomArModelRenderer", "lamp asset load failed", it) }
            .getOrNull()?.also {
                resourceLoader.loadResources(it); it.releaseSourceData()
            }
        sofaAsset = runCatching { assetLoader.createAsset(readAsset(SOFA_ASSET)) }
            .onFailure { android.util.Log.e("RoomArModelRenderer", "sofa asset load failed", it) }
            .getOrNull()?.also {
                resourceLoader.loadResources(it); it.releaseSourceData()
            }
        shadowAsset = runCatching { assetLoader.createAsset(readAsset(SHADOW_ASSET)) }
            .getOrNull()?.also {
                resourceLoader.loadResources(it); it.releaseSourceData()
                scene.addEntities(it.entities)   // always in the scene; parked off-screen when hidden
                val tm = engine.transformManager
                tm.setTransform(tm.getInstance(it.root), parkedMatrix())  // off-screen until first pose
            }
        // 2nd soft shadow quad — only used to complete the sofa's L footprint;
        // parked off-screen for chair / table / lamp.
        shadowAsset2 = runCatching { assetLoader.createAsset(readAsset(SHADOW_ASSET)) }
            .getOrNull()?.also {
                resourceLoader.loadResources(it); it.releaseSourceData()
                scene.addEntities(it.entities)
                val tm = engine.transformManager
                tm.setTransform(tm.getInstance(it.root), parkedMatrix())
            }
    }

    fun select(which: String) {
        mode = which
        // contact-shadow footprint radius (metres) per object:
        //  chair 0.70 x 0.72 m -> 0.42
        //  table: pedestal footprint is Ø0.68 m; use 0.40 so the shadow reads as a
        //  grounded blob just past the base without spreading to the Ø0.90 m top.
        //  lamp: ceramic base ~0.15 x 0.12 m -> 0.12
        //  (shadow tracks the base that touches the floor, not the Ø0.20 m shade)
        footRadius = when (which) {
            "table" -> 0.40f
            "lamp" -> 0.12f
            "sofa" -> 0.90f    // unused for the sofa (dual-quad path), kept sane as a fallback
            else -> 0.42f
        }
        val bundled = when (which) {
            "table" -> tableAsset ?: chairAsset   // fall back to chair if the table failed to load
            "lamp" -> lampAsset ?: chairAsset
            "sofa" -> sofaAsset ?: chairAsset
            else -> chairAsset
        }
        // A verified external (Storage-delivered) GLB, when present, replaces
        // the bundled asset for this product slot (Phase 9.2 R10).
        val next = externalAssets[which] ?: bundled
        if (next === current) return
        current?.let { scene.removeEntities(it.entities) }
        current = next
        current?.let { scene.addEntities(it.entities) }
    }

    /**
     * Phase 9.2 R10 — install a **verified** external GLB for [which]
     * ("chair"/"table"/"lamp"/"sofa"), or pass [absolutePath] = null to drop
     * any external override and fall back to the bundled asset for that slot.
     *
     * The file at [absolutePath] has already been magic-byte / declared-length /
     * chunk-structure / SHA-256 / bounding-box (±3 %) checked by
     * `RoomArModelService`; this method still fails safe (keeps the previous
     * asset) if Filament cannot parse it. Old Filament resources for the slot
     * are released here. Called on the platform-channel (main) thread, same as
     * [select].
     */
    fun setExternalModel(which: String, absolutePath: String?) {
        val prev = externalAssets[which]

        if (absolutePath == null) {
            if (prev == null) return
            if (current === prev) {
                scene.removeEntities(prev.entities)
                current = null
            }
            assetLoader.destroyAsset(prev)
            externalAssets.remove(which)
            if (which == mode) select(mode)   // restore the bundled asset
            return
        }

        val loaded = runCatching {
            val bytes = File(absolutePath).readBytes()
            val buf = ByteBuffer.allocateDirect(bytes.size).apply { put(bytes); rewind() }
            assetLoader.createAsset(buf)?.also {
                resourceLoader.loadResources(it)
                it.releaseSourceData()
            }
        }.onFailure {
            android.util.Log.e("RoomArModelRenderer", "external model load failed: $absolutePath", it)
        }.getOrNull() ?: return   // keep whatever was showing

        // If this slot is the one on screen, swap the visible asset now
        // (removing the bundled OR the prior external, whichever is current).
        if (which == mode) {
            current?.let { scene.removeEntities(it.entities) }
            current = loaded
            scene.addEntities(loaded.entities)
        }
        // Only ever destroy the previous EXTERNAL asset — never a bundled one.
        prev?.let { assetLoader.destroyAsset(it) }
        externalAssets[which] = loaded
        footRadius = when (which) {
            "table" -> 0.40f
            "lamp" -> 0.12f
            "sofa" -> 0.90f
            else -> 0.42f
        }
    }

    fun resetPlacement() { offsetX = 0.0; offsetZ = 0.0; yaw = 0.0 }

    fun start() {
        if (running) return
        running = true
        choreographer = Choreographer.getInstance()
        choreographer?.postFrameCallback(frameCallback)
    }

    fun stop() {
        running = false
        choreographer?.removeFrameCallback(frameCallback)
    }

    /**
     * Called from RoomArMarkerView.analyze() every processed frame.
     * [isVisible] = show the model this frame (a fresh detection OR a held pose
     * during the brief loss window). [r]/[t] non-null = a fresh pose to adopt;
     * null with isVisible=true = keep rendering the last pose (blur / occlusion).
     */
    fun updatePose(
        r: DoubleArray?, t: DoubleArray?,
        fxPx: Double, fyPx: Double, w: Int, h: Int, isVisible: Boolean,
    ) {
        fx = fxPx; fy = fyPx; imgW = w; imgH = h
        if (r != null && t != null) { rCV = r; tCV = t; haverPose = true }
        visible = isVisible && haverPose
    }

    // ---- per-frame render -----------------------------------------------
    private fun renderFrame(frameTimeNanos: Long) {
        val sc = swapChain ?: return
        val sw = surfaceW; val sh = surfaceH
        if (!uiHelper.isReadyToRender || sw == 0 || sh == 0 || imgW == 0 || fy <= 0.0) return

        // Viewport = the WHOLE surface, always, from the stored size. The camera
        // preview is FILL_CENTER (fills the surface, centre-cropping the image), so
        // the 3D layer must fill the same surface with a matching centre-cropped
        // projection — no letterbox, and it never drifts because we never read back
        // our own mutated viewport.
        view.viewport = Viewport(0, 0, sw, sh)

        val imgAspect = imgW.toDouble() / imgH
        val surfAspect = sw.toDouble() / sh
        val tanY = (imgH / 2.0) / fy               // full-image vertical half-FOV (tan)
        val tanX = (imgW / 2.0) / fx               // full-image horizontal half-FOV (tan)
        // FILL_CENTER: if the surface is narrower than the image we crop width and
        // keep the full vertical FOV; if wider, we crop height.
        val visTanY = if (surfAspect <= imgAspect) tanY else tanX / surfAspect
        val fovYdeg = Math.toDegrees(2.0 * kotlin.math.atan(visTanY))
        camera.setProjection(fovYdeg, surfAspect, 0.05, 30.0, Camera.Fov.VERTICAL)
        camera.setModelMatrix(IDENTITY.copyOf())

        val asset = current
        val tm = engine.transformManager
        if (asset != null && haverPose) {
            val (rs, ts) = smoother.filter(rCV, tCV, System.nanoTime())   // advance once/frame
            tm.setTransform(tm.getInstance(asset.root), modelMatrix(visible, rs, ts))
            if (mode == "sofa") {
                // L-footprint contact shadow: two overlapping soft ellipses.
                shadowAsset?.let { tm.setTransform(tm.getInstance(it.root), sofaShadowMatrix(visible, rs, ts, SOFA_SHADOW_MAIN)) }
                shadowAsset2?.let { tm.setTransform(tm.getInstance(it.root), sofaShadowMatrix(visible, rs, ts, SOFA_SHADOW_CHAISE)) }
            } else {
                shadowAsset?.let { tm.setTransform(tm.getInstance(it.root), shadowMatrix(visible, rs, ts)) }
                shadowAsset2?.let { tm.setTransform(tm.getInstance(it.root), parkedMatrix()) }
            }
        } else {
            // no pose yet -> keep everything off-screen (no startup flash at origin)
            asset?.let { tm.setTransform(tm.getInstance(it.root), parkedMatrix()) }
            shadowAsset?.let { tm.setTransform(tm.getInstance(it.root), parkedMatrix()) }
            shadowAsset2?.let { tm.setTransform(tm.getInstance(it.root), parkedMatrix()) }
        }

        if (renderer.beginFrame(sc, frameTimeNanos)) {
            renderer.render(view)
            renderer.endFrame()
        }
    }

    // marker -> OpenCV camera -> GL eye. Returns (Rlin 3x3 row-major, tc 3).
    private fun markerToEye(
        rs: DoubleArray, ts: DoubleArray, linMarker: DoubleArray, offMarker: DoubleArray,
    ): Pair<DoubleArray, DoubleArray> {
        val flip = doubleArrayOf(1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, -1.0) // diag(1,-1,-1)
        val Rc = mul3(flip, rs)
        val Rlin = mul3(Rc, linMarker)
        val ro = doubleArrayOf(
            rs[0] * offMarker[0] + rs[1] * offMarker[1] + rs[2] * offMarker[2] + ts[0],
            rs[3] * offMarker[0] + rs[4] * offMarker[1] + rs[5] * offMarker[2] + ts[1],
            rs[6] * offMarker[0] + rs[7] * offMarker[1] + rs[8] * offMarker[2] + ts[2],
        )
        return Pair(Rlin, doubleArrayOf(ro[0], -ro[1], -ro[2]))
    }

    private fun parkedMatrix(): FloatArray =
        floatArrayOf(1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, -1000f, 1f)

    private fun colMajor(Rlin: DoubleArray, tc: DoubleArray, push: Double): FloatArray {
        val m = FloatArray(16)
        m[0] = Rlin[0].toFloat(); m[1] = Rlin[3].toFloat(); m[2] = Rlin[6].toFloat(); m[3] = 0f
        m[4] = Rlin[1].toFloat(); m[5] = Rlin[4].toFloat(); m[6] = Rlin[7].toFloat(); m[7] = 0f
        m[8] = Rlin[2].toFloat(); m[9] = Rlin[5].toFloat(); m[10] = Rlin[8].toFloat(); m[11] = 0f
        m[12] = tc[0].toFloat(); m[13] = tc[1].toFloat(); m[14] = (tc[2] + push).toFloat(); m[15] = 1f
        return m
    }

    /** chair/table/lamp/sofa: diag(1,-1,-1) * [R|t]_cv * T(off) * Rz(yaw) * scale * Rx(+90deg).
     *  All product assets are authored +Y up / -Z front / floor-centred at true metre
     *  size, so the same transform places any of them. */
    private fun modelMatrix(showing: Boolean, rs: DoubleArray, ts: DoubleArray): FloatArray {
        val sMul = scaleMultiplier
        val cz = cos(yaw); val sz = sin(yaw)
        // Rx90 maps model-local (x,y,z) -> marker (x,-z,y): model +Y up -> marker +Z up
        val rx = doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0)
        for (i in rx.indices) rx[i] *= sMul
        val rz = doubleArrayOf(cz, -sz, 0.0, sz, cz, 0.0, 0.0, 0.0, 1.0)
        val L = mul3(rz, rx)
        val offMarker = doubleArrayOf(offsetX, offsetZ, 0.0)   // on the marker plane, stays on floor
        val (Rlin, tc) = markerToEye(rs, ts, L, offMarker)
        return colMajor(Rlin, tc, if (showing) 0.0 else -80.0)
    }

    /** Sofa L-footprint contact shadow: one restrained soft ellipse of the pair.
     *  [p] = model-local (centreX, centreZ, halfX, halfZ) metres. Unlike the round
     *  [shadowMatrix], this follows yaw so the L tracks rotation, and it is scaled
     *  per-axis (the radius-1 `shadow_blob` disc → an ellipse ≈ the plan bbox inset
     *  ~5 cm). Two of these overlap to approximate the L without a huge dark
     *  rectangle or an obviously-wrong disc. */
    private fun sofaShadowMatrix(
        showing: Boolean, rs: DoubleArray, ts: DoubleArray, p: DoubleArray,
    ): FloatArray {
        val m = scaleMultiplier
        val cz = cos(yaw); val sz = sin(yaw)
        val cX = p[0] * m; val cZ = p[1] * m
        val hX = p[2] * m; val hZ = p[3] * m
        // Rx90 maps model-local (x,y,z) -> marker (x,-z,y); S scales the local disc
        // per-axis in XZ; Rz(yaw) then spins the ellipse with the model.
        val rx = doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0)
        val S = doubleArrayOf(hX, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, hZ)
        val rz = doubleArrayOf(cz, -sz, 0.0, sz, cz, 0.0, 0.0, 0.0, 1.0)
        val L = mul3(rz, mul3(rx, S))
        // sub-shadow centre: local (cX,0,cZ) -> Rx90 -> (cX,-cZ,0) -> Rz(yaw)
        val ax = cX; val ay = -cZ
        val dxm = cz * ax - sz * ay
        val dym = sz * ax + cz * ay
        val offMarker = doubleArrayOf(offsetX + dxm, offsetZ + dym, 0.003)  // 3 mm above the sheet
        val (Rlin, tc) = markerToEye(rs, ts, L, offMarker)
        return colMajor(Rlin, tc, if (showing) 0.0 else -80.0)
    }

    /** flat contact shadow: same pose as the model, no yaw, scaled to the footprint,
     *  lifted a few mm off the marker sheet so it reads as a blob under the base. */
    private fun shadowMatrix(showing: Boolean, rs: DoubleArray, ts: DoubleArray): FloatArray {
        val r = (footRadius * scaleMultiplier).toDouble()
        // disc is in local XZ (y=0); scale X,Z by radius, keep Y (thickness irrelevant)
        val rx = doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0)
        val S = doubleArrayOf(r, 0.0, 0.0, 0.0, r, 0.0, 0.0, 0.0, r)
        val L = mul3(rx, S)
        val offMarker = doubleArrayOf(offsetX, offsetZ, 0.003)  // 3 mm above the sheet
        val (Rlin, tc) = markerToEye(rs, ts, L, offMarker)
        return colMajor(Rlin, tc, if (showing) 0.0 else -80.0)
    }

    fun destroy() {
        stop()
        uiHelper.detach()
        engine.flushAndWait()
        current?.let { scene.removeEntities(it.entities) }
        shadowAsset?.let { scene.removeEntities(it.entities); assetLoader.destroyAsset(it) }
        shadowAsset2?.let { scene.removeEntities(it.entities); assetLoader.destroyAsset(it) }
        chairAsset?.let { assetLoader.destroyAsset(it) }
        tableAsset?.let { assetLoader.destroyAsset(it) }
        lampAsset?.let { assetLoader.destroyAsset(it) }
        sofaAsset?.let { assetLoader.destroyAsset(it) }
        externalAssets.values.forEach { it?.let { a -> assetLoader.destroyAsset(a) } }
        externalAssets.clear()
        indirect?.let { engine.destroyIndirectLight(it) }
        if (sunEntity != 0) { scene.removeEntity(sunEntity); engine.destroyEntity(sunEntity) }
        if (fillEntity != 0) { scene.removeEntity(fillEntity); engine.destroyEntity(fillEntity) }
        resourceLoader.destroy()
        assetLoader.destroy()
        materialProvider.destroyMaterials()
        engine.destroyRenderer(renderer)
        engine.destroyView(view)
        engine.destroyScene(scene)
        engine.destroyCameraComponent(cameraEntity)
        swapChain?.let { engine.destroySwapChain(it) }
        engine.destroy()
    }
}

private val IDENTITY = floatArrayOf(
    1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f,
)

private fun mul3(a: DoubleArray, b: DoubleArray): DoubleArray {
    val o = DoubleArray(9)
    for (r in 0 until 3) for (c in 0 until 3) {
        var s = 0.0
        for (k in 0 until 3) s += a[r * 3 + k] * b[k * 3 + c]
        o[r * 3 + c] = s
    }
    return o
}

/**
 * One-Euro filter on translation (3 scalars) + rotation (quaternion), matching
 * SCALE_CONTRACT.md: minCutoff 1.1 Hz, beta 0.006, dCutoff 1.0 Hz.
 */
private class PoseSmoother {
    private val minCutoff = 1.1
    private val beta = 0.006
    private val dCutoff = 1.0

    private var lastNs = 0L
    private val tPrev = DoubleArray(3)
    private val tDeriv = DoubleArray(3)
    private var qPrev = DoubleArray(4)
    private val qDeriv = DoubleArray(4)
    private var primed = false

    private fun alpha(cutoff: Double, dt: Double): Double {
        val tau = 1.0 / (2.0 * PI * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    fun filter(r: DoubleArray, t: DoubleArray, nowNs: Long): Pair<DoubleArray, DoubleArray> {
        var q = matToQuat(r)
        if (!primed) {
            primed = true
            lastNs = nowNs
            System.arraycopy(t, 0, tPrev, 0, 3)
            qPrev = q
            return Pair(r.copyOf(), t.copyOf())
        }
        var dt = (nowNs - lastNs) / 1e9
        if (dt <= 0.0 || dt > 0.5) dt = 1.0 / 20.0
        lastNs = nowNs

        val outT = DoubleArray(3)
        for (i in 0 until 3) {
            val d = (t[i] - tPrev[i]) / dt
            val ad = alpha(dCutoff, dt)
            tDeriv[i] = ad * d + (1 - ad) * tDeriv[i]
            val cutoff = minCutoff + beta * abs(tDeriv[i])
            val a = alpha(cutoff, dt)
            outT[i] = a * t[i] + (1 - a) * tPrev[i]
            tPrev[i] = outT[i]
        }

        if (dot4(q, qPrev) < 0.0) for (i in 0 until 4) q[i] = -q[i]
        val outQ = DoubleArray(4)
        var speed = 0.0
        for (i in 0 until 4) speed += abs((q[i] - qPrev[i]) / dt)
        for (i in 0 until 4) {
            val d = (q[i] - qPrev[i]) / dt
            val ad = alpha(dCutoff, dt)
            qDeriv[i] = ad * d + (1 - ad) * qDeriv[i]
            val cutoff = minCutoff + beta * speed
            val a = alpha(cutoff, dt)
            outQ[i] = a * q[i] + (1 - a) * qPrev[i]
        }
        normalize4(outQ)
        System.arraycopy(outQ, 0, qPrev, 0, 4)
        return Pair(quatToMat(outQ), outT)
    }

    private fun dot4(a: DoubleArray, b: DoubleArray) =
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]

    private fun normalize4(q: DoubleArray) {
        val n = sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]).let { if (it == 0.0) 1.0 else it }
        for (i in 0 until 4) q[i] /= n
    }

    private fun matToQuat(m: DoubleArray): DoubleArray {
        val tr = m[0] + m[4] + m[8]
        val q = DoubleArray(4)
        if (tr > 0) {
            val s = sqrt(tr + 1.0) * 2
            q[0] = 0.25 * s; q[1] = (m[7] - m[5]) / s; q[2] = (m[2] - m[6]) / s; q[3] = (m[3] - m[1]) / s
        } else if (m[0] > m[4] && m[0] > m[8]) {
            val s = sqrt(1.0 + m[0] - m[4] - m[8]) * 2
            q[0] = (m[7] - m[5]) / s; q[1] = 0.25 * s; q[2] = (m[1] + m[3]) / s; q[3] = (m[2] + m[6]) / s
        } else if (m[4] > m[8]) {
            val s = sqrt(1.0 + m[4] - m[0] - m[8]) * 2
            q[0] = (m[2] - m[6]) / s; q[1] = (m[1] + m[3]) / s; q[2] = 0.25 * s; q[3] = (m[5] + m[7]) / s
        } else {
            val s = sqrt(1.0 + m[8] - m[0] - m[4]) * 2
            q[0] = (m[3] - m[1]) / s; q[1] = (m[2] + m[6]) / s; q[2] = (m[5] + m[7]) / s; q[3] = 0.25 * s
        }
        normalize4(q)
        return q
    }

    private fun quatToMat(q: DoubleArray): DoubleArray {
        val w = q[0]; val x = q[1]; val y = q[2]; val z = q[3]
        return doubleArrayOf(
            1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y),
            2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x),
            2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y),
        )
    }
}
