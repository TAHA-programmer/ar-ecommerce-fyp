package com.tahafayyaz.twin_ar.roomar

import android.content.Context
import android.opengl.Matrix
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

/**
 * TWin AR — Phase 9.2 R6 Tier-1 ARCore product overlay.
 *
 * Renders one validated glTF product model into a transparent [TextureView]
 * layered on top of [RoomArCoreRenderer]'s `GLSurfaceView` (real camera
 * passthrough + plane/reticle drawing) — the exact same "TextureView over the
 * real camera layer" composition already proven for Tier 2
 * ([RoomArModelRenderer]) and reused verbatim for Tier 3
 * ([RoomArPreviewRenderer]).
 *
 * No marker math, no orbit camera: ARCore already supplies a real, metric
 * camera pose every frame. Filament's own camera is kept at the identity
 * transform (matching the established pattern in the other two renderers)
 * and the ARCore view matrix is baked directly into the model's world
 * transform instead — `eyeSpace = ARCore.viewMatrix * anchor.pose * yaw`,
 * so `Filament.projection(ARCore.projectionMatrix) * eyeSpace` is exactly
 * the same clip-space transform ARCore's own renderer would use. No pose
 * smoothing is applied — ARCore's own tracking is already the source of
 * truth for "where is the real world", unlike Tier 2's per-frame solvePnP
 * pose (which the One-Euro filter exists to stabilise).
 *
 * All GLBs are authored in metres, +Y up, floor-centred (`SCALE_CONTRACT.md`),
 * so placing the model root exactly at the anchor pose puts its floor-contact
 * base exactly on the detected surface — never floating or sinking.
 */
class RoomArCoreModelRenderer(
    context: Context,
    initialMode: String = "chair",
) {

    companion object {
        init { Utils.init() }
        private const val TAG = "RoomArCoreModelRenderer"
        private const val CHAIR_ASSET = "luna_accent_chair.glb"
        private const val TABLE_ASSET = "round_wood_coffee_table.glb"
        private const val LAMP_ASSET = "modern_table_lamp.glb"
        private const val SOFA_ASSET = "luna_right_chaise_sofa.glb"
    }

    val textureView = TextureView(context).apply { isOpaque = false }

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
        this.scene = this@RoomArCoreModelRenderer.scene
        this.camera = this@RoomArCoreModelRenderer.camera
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
    private var current: FilamentAsset? = null
    private var mode = initialMode.ifBlank { "chair" }

    private var sunEntity = 0
    private var fillEntity = 0
    private var indirect: IndirectLight? = null

    @Volatile private var surfaceW = 0
    @Volatile private var surfaceH = 0

    // live ARCore camera pose, updated from the GL thread every tracked frame.
    @Volatile private var viewMatrix: FloatArray? = null
    @Volatile private var projMatrix: FloatArray? = null
    // world-space anchor pose (column-major 4x4), or null = nothing placed yet.
    @Volatile private var anchorMatrix: FloatArray? = null
    @Volatile var yawDegrees: Float = 0f

    private var choreographer: Choreographer? = null
    private var running = false
    private var lastRenderNs = 0L
    private val minFramePeriodNs = 16_000_000L // ~60 fps
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
        camera.setModelMatrix(IDENTITY.copyOf())
        // Select the opened product's model synchronously, during
        // construction — a post-construction `select()`/`setExternalModel()`
        // channel call from Flutter races the PlatformView's own creation
        // (`RoomArCorePlugin.activeView` is still null when
        // `RoomArCoreViewModel.start()` fires its first channel calls) and
        // gets silently dropped, exactly the bug already fixed once for the
        // R16 Admin preview (`RoomArPreviewRenderer`'s `initialMode`). Without
        // this, `current` never gets set at all and nothing ever renders,
        // even though ARCore's own tracking/hit-test/anchor keep working
        // correctly (they don't depend on this class).
        select(mode)
    }

    private fun setupLighting() {
        indirect = IndirectLight.Builder()
            .irradiance(1, floatArrayOf(0.78f, 0.78f, 0.80f))
            .intensity(32_000f)
            .build(engine)
        scene.indirectLight = indirect

        sunEntity = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 0.98f, 0.95f).intensity(90_000f)
            .direction(0.4f, -0.85f, -0.3f).castShadows(false)
            .build(engine, sunEntity)
        scene.addEntity(sunEntity)

        fillEntity = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.9f, 0.93f, 1.0f).intensity(28_000f)
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
    }

    /** Same fallback contract as [RoomArPreviewRenderer.bundledFor]: the four
     *  originally-bundled products have a byte-identical local fallback;
     *  every other product (coverage-expansion, or any future Admin-created
     *  one) has none — `null` here means "wait for a verified external GLB,
     *  never substitute the wrong model". */
    private fun bundledFor(which: String): FilamentAsset? = when (which) {
        "chair" -> chairAsset
        "table" -> tableAsset ?: chairAsset
        "lamp" -> lampAsset ?: chairAsset
        "sofa" -> sofaAsset ?: chairAsset
        else -> null
    }

    fun select(which: String) {
        mode = which
        val next = externalAssets[which] ?: bundledFor(which)
        if (next === current) return
        current?.let { scene.removeEntities(it.entities) }
        current = next
        current?.let { scene.addEntities(it.entities) }
    }

    /** Install a **verified** external GLB for [which] (see
     *  `RoomArModelService`'s verification contract), or [absolutePath] =
     *  null to drop the override and fall back to the bundled asset. */
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
        val loaded = runCatching {
            val bytes = File(absolutePath).readBytes()
            makeAsset(ByteBuffer.allocateDirect(bytes.size).apply { put(bytes); rewind() })
        }.onFailure {
            Log.e(TAG, "external model load failed: $absolutePath", it)
        }.getOrNull()
        if (loaded == null) return
        if (which == mode) {
            current?.let { scene.removeEntities(it.entities) }
            current = loaded
            scene.addEntities(loaded.entities)
        }
        prev?.let { assetLoader.destroyAsset(it) }
        externalAssets[which] = loaded
    }

    /** Called every tracked frame from [RoomArCoreRenderer]'s GL thread. */
    fun updateCameraPose(view: FloatArray, projection: FloatArray) {
        viewMatrix = view
        projMatrix = projection
    }

    /** [pose] = the placed anchor's world-space 4x4 (column-major), or `null`
     *  once nothing is placed / the anchor is removed. Called from the GL
     *  thread. */
    fun updateAnchorPose(pose: FloatArray?) {
        anchorMatrix = pose
    }

    fun resetYaw() { yawDegrees = 0f }

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

        val proj = projMatrix
        val v = viewMatrix
        val anchor = anchorMatrix
        val asset = current

        if (proj != null) {
            val projD = DoubleArray(16) { proj[it].toDouble() }
            camera.setCustomProjection(projD, 0.05, 30.0)
        }

        val tm = engine.transformManager
        if (asset != null && v != null && anchor != null) {
            // model-local yaw around its own +Y axis, then place at the anchor,
            // then transform world -> eye with ARCore's own view matrix — the
            // same "bake the view into the model, keep the Filament camera at
            // identity" trick RoomArModelRenderer/RoomArPreviewRenderer use.
            val yawMat = FloatArray(16)
            Matrix.setRotateM(yawMat, 0, yawDegrees, 0f, 1f, 0f)
            val world = FloatArray(16)
            Matrix.multiplyMM(world, 0, anchor, 0, yawMat, 0)
            val eye = FloatArray(16)
            Matrix.multiplyMM(eye, 0, v, 0, world, 0)
            tm.setTransform(tm.getInstance(asset.root), eye)
        } else {
            asset?.let { tm.setTransform(tm.getInstance(it.root), parkedMatrix()) }
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
