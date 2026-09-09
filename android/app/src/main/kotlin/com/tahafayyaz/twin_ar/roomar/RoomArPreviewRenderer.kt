package com.tahafayyaz.twin_ar.roomar

import android.content.Context
import android.util.Log
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
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * TWin AR — Phase 9.2 R7 Tier-3 Interactive 3D Preview renderer.
 *
 * A **no-camera** Filament orbit viewer for one validated product GLB
 * (chair / table / lamp / sofa). It renders into a transparent [TextureView]
 * (the Flutter side paints the themed backdrop behind it), frames the model
 * upright on an implied floor at y = 0, and exposes orbit / pan / pinch-zoom /
 * reset from Flutter.
 *
 * Deliberately separate from [RoomArModelRenderer] (the physically-approved
 * marker overlay) — no marker pose, no camera intrinsics, no shared state — so
 * the Tier-2 path is untouched. Engine / lighting / asset-loading setup mirrors
 * the marker renderer; the every-frame camera is a simple spherical orbit.
 *
 * All GLBs are authored in metres, +Y up, front = −Z, floor-centred
 * (`SCALE_CONTRACT.md`), so `select()` needs no per-model transform — the model
 * sits at the origin and the orbit target defaults to its bounding-box centre.
 */
class RoomArPreviewRenderer(
    context: Context,
    initialMode: String = "chair",
    initialPath: String? = null,
) {

    companion object {
        init { Utils.init() }
        private const val TAG = "RoomArPreviewRenderer"
        private const val CHAIR_ASSET = "luna_accent_chair.glb"
        private const val TABLE_ASSET = "round_wood_coffee_table.glb"
        private const val LAMP_ASSET = "modern_table_lamp.glb"
        private const val SOFA_ASSET = "luna_right_chaise_sofa.glb"
        private const val SHADOW_ASSET = "shadow_blob.glb"
        private const val FOV_DEG = 45.0

        // Every GLB is authored front = −Z (`SCALE_CONTRACT.md`). The orbit
        // camera sits on the −Z side (so `cos(azimuth) < 0`) looking toward the
        // model, rotated ~29° so the customer sees a front-left three-quarter
        // view on open — never the back. `frame()` / `reset()` return here.
        private const val FRAME_AZIMUTH = PI + 0.5
        private const val FRAME_ELEVATION = 0.20   // rad, a little above eye level
    }

    val textureView = TextureView(context).apply { isOpaque = false }

    /** "loading" | "ready" | "failed" — pushed to Flutter for honest UI. */
    var onLoadState: ((String) -> Unit)? = null

    private val engine = Engine.create()
    private val renderer = engine.createRenderer().apply {
        clearOptions = Renderer.ClearOptions().apply {
            clear = true
            clearColor = floatArrayOf(0f, 0f, 0f, 0f)
        }
    }
    private val scene = engine.createScene()
    private val cameraEntity = EntityManager.get().create()
    private val camera = engine.createCamera(cameraEntity)
    private val view = engine.createView().apply {
        this.scene = this@RoomArPreviewRenderer.scene
        this.camera = this@RoomArPreviewRenderer.camera
        blendMode = View.BlendMode.TRANSLUCENT
        isPostProcessingEnabled = true
    }

    private val materialProvider = UbershaderProvider(engine)
    private val assetLoader = AssetLoader(engine, materialProvider, EntityManager.get())
    private val resourceLoader = ResourceLoader(engine)

    private val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK).apply {
        isOpaque = false
    }

    private var swapChain: SwapChain? = null
    private val appContext = context.applicationContext

    private var chairAsset: FilamentAsset? = null
    private var tableAsset: FilamentAsset? = null
    private var lampAsset: FilamentAsset? = null
    private var sofaAsset: FilamentAsset? = null
    private val externalAssets = HashMap<String, FilamentAsset?>()
    private var shadowAsset: FilamentAsset? = null
    private var current: FilamentAsset? = null
    // "chair"/"table"/"lamp"/"sofa" pick a bundled asset; any other non-blank
    // key (e.g. "admin" from the R16 Admin AR & Media preview) is kept as-is so
    // a later setExternalModel(thatKey, path) displays — bundledFor() falls back
    // to the chair for the brief moment before the external GLB arrives.
    private var mode = initialMode.ifBlank { "chair" }

    private var sunEntity = 0
    private var fillEntity = 0
    private var indirect: IndirectLight? = null

    @Volatile private var surfaceW = 0
    @Volatile private var surfaceH = 0

    // ── orbit state ─────────────────────────────────────────────────────────
    // Spherical camera around a target point. Defaults framed in [frame()].
    @Volatile private var azimuth = FRAME_AZIMUTH    // rad — front-left 3/4
    @Volatile private var elevation = FRAME_ELEVATION
    @Volatile private var distance = 2.0             // metres
    @Volatile private var panX = 0.0                 // world-space, camera-right
    @Volatile private var panY = 0.0                 // world-space, camera-up
    private var minDistance = 0.4
    private var maxDistance = 12.0
    private var frameDistance = 2.0
    private var frameElevation = FRAME_ELEVATION
    private var frameAzimuth = FRAME_AZIMUTH
    private val target = doubleArrayOf(0.0, 0.4, 0.0)   // model bbox centre
    private var modelRadius = 0.6

    private var choreographer: Choreographer? = null
    private var running = false
    private var lastRenderNs = 0L
    private val minFramePeriodNs = 16_000_000L   // ~60 fps cap for a smooth orbit
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
        loadBundledAssets()
        select(mode)
        // Phase 9.2 R16 — the admin preview passes the exact `.glb` to show as a
        // creation param (`path`), so the first model shown never depends on a
        // post-creation `setModel` channel call. `select(mode)` above framed the
        // bundled fallback for an unknown key ("admin" -> chair); this swaps the
        // real file in right away. `which == mode` here, so it displays.
        if (!initialPath.isNullOrBlank()) setExternalModel(mode, initialPath)
    }

    private fun setupLighting() {
        indirect = IndirectLight.Builder()
            .irradiance(1, floatArrayOf(0.74f, 0.74f, 0.78f))
            .intensity(34_000f)
            .build(engine)
        scene.indirectLight = indirect

        sunEntity = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 0.98f, 0.95f).intensity(80_000f)
            .direction(0.4f, -0.85f, -0.3f).castShadows(false)
            .build(engine, sunEntity)
        scene.addEntity(sunEntity)

        fillEntity = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.9f, 0.93f, 1.0f).intensity(26_000f)
            .direction(-0.45f, -0.15f, 0.55f).castShadows(false)
            .build(engine, fillEntity)
        scene.addEntity(fillEntity)
    }

    private fun readAsset(name: String): ByteBuffer {
        val bytes = appContext.assets.open(name).use { it.readBytes() }
        return ByteBuffer.allocateDirect(bytes.size).apply { put(bytes); rewind() }
    }

    private fun makeAsset(bytes: ByteBuffer): FilamentAsset? =
        assetLoader.createAsset(bytes)?.also {
            resourceLoader.loadResources(it); it.releaseSourceData()
        }

    private fun loadBundledAssets() {
        chairAsset = runCatching { makeAsset(readAsset(CHAIR_ASSET)) }
            .onFailure { Log.e(TAG, "chair load failed", it) }.getOrNull()
        tableAsset = runCatching { makeAsset(readAsset(TABLE_ASSET)) }
            .onFailure { Log.e(TAG, "table load failed", it) }.getOrNull()
        lampAsset = runCatching { makeAsset(readAsset(LAMP_ASSET)) }
            .onFailure { Log.e(TAG, "lamp load failed", it) }.getOrNull()
        sofaAsset = runCatching { makeAsset(readAsset(SOFA_ASSET)) }
            .onFailure { Log.e(TAG, "sofa load failed", it) }.getOrNull()
        shadowAsset = runCatching { makeAsset(readAsset(SHADOW_ASSET)) }
            .getOrNull()?.also {
                scene.addEntities(it.entities)
                val tm = engine.transformManager
                tm.setTransform(tm.getInstance(it.root), parkedMatrix())
            }
    }

    private fun bundledFor(which: String): FilamentAsset? {
        val exact = when (which) {
            "chair" -> chairAsset
            "table" -> tableAsset ?: chairAsset   // bundled table failed to parse — fall back to the guaranteed chair
            "lamp" -> lampAsset ?: chairAsset
            "sofa" -> sofaAsset ?: chairAsset
            // Admin preview (R16) always supplies a real path synchronously
            // at construction (`initialPath`) — this is a safety net for a
            // caller that is never a real customer scenario, so it keeps the
            // pre-existing chair fallback.
            "admin" -> chairAsset
            // Phase 9.2 coverage-expansion — a customer product outside the
            // four originally-bundled ones (keyed by its own Firestore
            // product id) has no bundled counterpart at all. Returning null
            // here means `select()` reports "failed" until a verified
            // external asset arrives — an honest state, never a silently
            // wrong substitute model.
            else -> null
        }
        if (exact == null) {
            Log.d(TAG, "no bundled asset for mode '$which' — an external model is required")
        }
        return exact
    }

    fun select(which: String) {
        mode = which
        val next = externalAssets[which] ?: bundledFor(which)
        if (next === current) return
        onLoadState?.invoke("loading")
        current?.let { scene.removeEntities(it.entities) }
        current = next
        current?.let { scene.addEntities(it.entities) }
        frame()
        onLoadState?.invoke(if (current != null) "ready" else "failed")
    }

    /**
     * Phase 9.2 R7/R10 — install a **verified** external GLB for [which], or
     * pass [absolutePath] = null to drop the override and fall back to the
     * bundled asset. [absolutePath] has already been magic-byte / length /
     * structure / SHA-256 / bounding-box checked by `RoomArModelService`; this
     * still fails safe (keeps the previous asset) if Filament cannot parse it.
     */
    fun setExternalModel(which: String, absolutePath: String?) {
        val prev = externalAssets[which]
        if (absolutePath == null) {
            if (prev == null) return
            if (current === prev) { scene.removeEntities(prev.entities); current = null }
            assetLoader.destroyAsset(prev)
            externalAssets.remove(which)
            if (which == mode) select(mode)
            return
        }
        onLoadState?.invoke("loading")
        val loaded = runCatching {
            val bytes = File(absolutePath).readBytes()
            makeAsset(ByteBuffer.allocateDirect(bytes.size).apply { put(bytes); rewind() })
        }.onFailure {
            Log.e(TAG, "external model load failed: $absolutePath", it)
        }.getOrNull()
        if (loaded == null) {
            // keep whatever was showing; report honestly
            onLoadState?.invoke(if (current != null) "ready" else "failed")
            return
        }
        if (which == mode) {
            current?.let { scene.removeEntities(it.entities) }
            current = loaded
            scene.addEntities(loaded.entities)
            frame()
        }
        prev?.let { assetLoader.destroyAsset(it) }
        externalAssets[which] = loaded
        onLoadState?.invoke("ready")
    }

    // ── framing + orbit ─────────────────────────────────────────────────────

    private fun frame() {
        val a = current
        if (a == null) { modelRadius = 0.6 } else {
            val box = a.boundingBox              // center[3], halfExtent[3]
            val c = box.center; val he = box.halfExtent
            target[0] = c[0].toDouble(); target[1] = c[1].toDouble(); target[2] = c[2].toDouble()
            modelRadius = max(
                0.05,
                sqrt((he[0] * he[0] + he[1] * he[1] + he[2] * he[2]).toDouble()),
            )
        }
        val halfFov = Math.toRadians(FOV_DEG / 2.0)
        frameDistance = (modelRadius / sin(halfFov)) * 1.45
        distance = frameDistance
        minDistance = max(0.15, modelRadius * 0.6)
        maxDistance = modelRadius * 9.0
        azimuth = frameAzimuth; elevation = frameElevation
        panX = 0.0; panY = 0.0
    }

    fun orbit(dxPx: Double, dyPx: Double) {
        val k = 0.01
        azimuth -= dxPx * k
        elevation = (elevation - dyPx * k).coerceIn(-1.30, 1.45)
    }

    fun zoom(scale: Double) {
        if (!scale.isFinite() || scale <= 0.0) return
        distance = (distance / scale).coerceIn(minDistance, maxDistance)
    }

    fun pan(dxPx: Double, dyPx: Double) {
        // convert screen drag to a world offset in the camera's right/up plane,
        // scaled by distance so the model tracks the finger regardless of zoom.
        val sh = if (surfaceH > 0) surfaceH.toDouble() else 1920.0
        val worldPerPx = (2.0 * distance * tan(Math.toRadians(FOV_DEG / 2.0))) / sh
        panX -= dxPx * worldPerPx
        panY += dyPx * worldPerPx
    }

    fun reset() {
        azimuth = frameAzimuth
        elevation = frameElevation
        distance = frameDistance
        panX = 0.0; panY = 0.0
    }

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

    private fun parkedMatrix(): FloatArray =
        floatArrayOf(1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, -1000f, 1f)

    private fun renderFrame(frameTimeNanos: Long) {
        val sc = swapChain ?: return
        val sw = surfaceW; val sh = surfaceH
        if (!uiHelper.isReadyToRender || sw == 0 || sh == 0) return
        view.viewport = Viewport(0, 0, sw, sh)

        val aspect = sw.toDouble() / sh
        camera.setProjection(FOV_DEG, aspect, 0.02, maxDistance * 3.0, Camera.Fov.VERTICAL)

        // camera basis
        val ce = cos(elevation); val se = sin(elevation)
        val ca = cos(azimuth); val sa = sin(azimuth)
        val dir = doubleArrayOf(ce * sa, se, ce * ca)          // target -> eye
        // right = normalize(dir x up), up' = right x dir
        val up = doubleArrayOf(0.0, 1.0, 0.0)
        var rx = dir[1] * up[2] - dir[2] * up[1]
        var ry = dir[2] * up[0] - dir[0] * up[2]
        var rz = dir[0] * up[1] - dir[1] * up[0]
        val rn = sqrt(rx * rx + ry * ry + rz * rz).let { if (it == 0.0) 1.0 else it }
        rx /= rn; ry /= rn; rz /= rn
        val ux = ry * dir[2] - rz * dir[1]
        val uy = rz * dir[0] - rx * dir[2]
        val uz = rx * dir[1] - ry * dir[0]

        val tx = target[0] + rx * panX + ux * panY
        val ty = target[1] + ry * panX + uy * panY
        val tz = target[2] + rz * panX + uz * panY
        val ex = tx + dir[0] * distance
        val ey = ty + dir[1] * distance
        val ez = tz + dir[2] * distance
        camera.lookAt(ex, ey, ez, tx, ty, tz, 0.0, 1.0, 0.0)

        // ground contact shadow: a static soft disc at the model footprint.
        val tm = engine.transformManager
        shadowAsset?.let {
            val r = (modelRadius * 0.78)
            val m = floatArrayOf(
                r.toFloat(), 0f, 0f, 0f,
                0f, r.toFloat(), 0f, 0f,
                0f, 0f, r.toFloat(), 0f,
                target[0].toFloat(), 0.002f, target[2].toFloat(), 1f,
            )
            tm.setTransform(tm.getInstance(it.root), if (current != null) m else parkedMatrix())
        }

        if (renderer.beginFrame(sc, frameTimeNanos)) {
            renderer.render(view)
            renderer.endFrame()
        }
    }

    fun destroy() {
        stop()
        uiHelper.detach()
        engine.flushAndWait()
        current?.let { scene.removeEntities(it.entities) }
        shadowAsset?.let { scene.removeEntities(it.entities); assetLoader.destroyAsset(it) }
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
