package com.tahafayyaz.twin_ar.roomar

import android.content.Context
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import android.view.TextureView

/**
 * TWin AR — Phase 9.2 R6 Tier-1 markerless-ARCore camera+plane layer host.
 *
 * Renders [RoomArCoreRenderer] into a [TextureView] with a hand-managed EGL
 * context and a dedicated render thread — **not** [android.opengl
 * .GLSurfaceView] (tracker §26).
 *
 * Root cause this replaces: a raw `GLSurfaceView` — backed by `SurfaceView`
 * — rendered correctly when embedded inside a Flutter `AndroidView` (the
 * camera passthrough and plane outlines were visibly correct in physical
 * testing) but its touch events never reached Flutter's gesture system —
 * confirmed by an on-screen tap counter staying at zero after 5-10 taps
 * over several seconds, with tracking and model-loading otherwise healthy.
 * This is a well-documented `SurfaceView`-in-`AndroidView` limitation, and
 * exactly why this project's own, already-physically-proven Tier-2 camera
 * layer uses CameraX's `PreviewView` in `ImplementationMode.COMPATIBLE`
 * (forcing a `TextureView` internally) instead of its default `SurfaceView`
 * mode, and why the Filament product overlay
 * ([RoomArCoreModelRenderer]/[RoomArPreviewRenderer]/[RoomArModelRenderer])
 * already renders into a plain `TextureView`. This class brings the ARCore
 * camera/plane layer onto that same, already-proven foundation.
 *
 * [RoomArCoreRenderer] itself is unchanged and still implements
 * `GLSurfaceView.Renderer` — every method on that interface only calls
 * static `GLES20`/`GLES11Ext` functions against whatever EGL context is
 * current on the calling thread; none of them actually use the `GL10`/
 * `EGLConfig` objects `GLSurfaceView` would normally have passed in. That
 * makes it safe to drive manually from here (passing `null` for both),
 * exactly like `GLSurfaceView` would have driven it, just with an EGL
 * context bound to this class's own `TextureView`-backed surface instead of
 * a `SurfaceView`'s.
 */
class RoomArCoreGlHost(
    context: Context,
    private val renderer: RoomArCoreRenderer,
) : TextureView.SurfaceTextureListener {

    private val tag = "RoomArCoreGlHost"

    val textureView = TextureView(context).apply {
        isOpaque = false
        surfaceTextureListener = this@RoomArCoreGlHost
    }

    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var nativeSurface: Surface? = null

    private var renderThread: HandlerThread? = null
    private var renderHandler: Handler? = null

    @Volatile private var running = false
    @Volatile private var eglReady = false

    private val frameRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            drawFrame()
            renderHandler?.postDelayed(this, FRAME_PERIOD_MS)
        }
    }

    // ── TextureView.SurfaceTextureListener — always called on the MAIN thread ──

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
        startRenderThread(surface, width, height)
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
        renderHandler?.post {
            if (eglReady) renderer.onSurfaceChanged(null, width, height)
        }
    }

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        stopRenderThread()
        return true // this class owns releasing the SurfaceTexture (via the Surface wrapping it)
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

    // ── public lifecycle (mirrors GLSurfaceView.onResume/onPause's role) ────

    /** Resumes the frame loop if the render thread already exists (a no-op —
     *  and harmless — if the surface hasn't been created yet; the frame loop
     *  starts on its own once it is). */
    fun resume() {
        if (renderThread == null || running) return
        running = true
        renderHandler?.post(frameRunnable)
    }

    /** Pauses the frame loop without tearing down the EGL context/thread —
     *  the `SurfaceTexture` normally survives an app background/foreground
     *  cycle, so there is nothing to rebuild on [resume]. */
    fun pause() {
        running = false
    }

    fun destroy() {
        stopRenderThread()
    }

    // ── render thread lifecycle ──────────────────────────────────────────────

    private fun startRenderThread(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        if (renderThread != null) return
        val thread = HandlerThread("RoomArCoreGL").apply { start() }
        renderThread = thread
        val handler = Handler(thread.looper)
        renderHandler = handler
        running = true
        handler.post {
            try {
                initEgl(surfaceTexture)
                renderer.onSurfaceCreated(null, null)
                renderer.onSurfaceChanged(null, width, height)
                eglReady = true
            } catch (t: Throwable) {
                Log.e(tag, "EGL init failed", t)
                running = false
                return@post
            }
            handler.post(frameRunnable)
        }
    }

    private fun stopRenderThread() {
        running = false
        val handler = renderHandler
        val thread = renderThread
        renderHandler = null
        renderThread = null
        if (handler == null || thread == null) return
        handler.post { releaseEgl() }
        thread.quitSafely()
    }

    private fun drawFrame() {
        if (!eglReady) return
        val display = eglDisplay
        val surface = eglSurface
        if (display == EGL14.EGL_NO_DISPLAY || surface == EGL14.EGL_NO_SURFACE) return
        if (!EGL14.eglMakeCurrent(display, surface, surface, eglContext)) {
            Log.w(tag, "eglMakeCurrent failed: ${EGL14.eglGetError()}")
            return
        }
        renderer.onDrawFrame(null)
        if (!EGL14.eglSwapBuffers(display, surface)) {
            Log.w(tag, "eglSwapBuffers failed: ${EGL14.eglGetError()}")
        }
    }

    private fun initEgl(surfaceTexture: SurfaceTexture) {
        val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(display != EGL14.EGL_NO_DISPLAY) { "eglGetDisplay failed" }
        eglDisplay = display

        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize failed" }

        val attribs = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_DEPTH_SIZE, 16,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        check(
            EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, numConfigs, 0) &&
                numConfigs[0] > 0,
        ) { "eglChooseConfig failed" }
        val config = configs[0] ?: error("no EGL config returned")

        val contextAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        val context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
        check(context != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }
        eglContext = context

        val surface = Surface(surfaceTexture)
        nativeSurface = surface
        val windowSurface = EGL14.eglCreateWindowSurface(
            display, config, surface, intArrayOf(EGL14.EGL_NONE), 0,
        )
        check(windowSurface != EGL14.EGL_NO_SURFACE) { "eglCreateWindowSurface failed" }
        eglSurface = windowSurface

        check(EGL14.eglMakeCurrent(display, windowSurface, windowSurface, context)) {
            "eglMakeCurrent (initial) failed"
        }
    }

    private fun releaseEgl() {
        val display = eglDisplay
        if (display != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglMakeCurrent(
                display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT,
            )
            if (eglSurface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, eglSurface)
            if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, eglContext)
        }
        eglDisplay = EGL14.EGL_NO_DISPLAY
        eglSurface = EGL14.EGL_NO_SURFACE
        eglContext = EGL14.EGL_NO_CONTEXT
        nativeSurface?.release()
        nativeSurface = null
        eglReady = false
    }

    companion object {
        // ~60 fps cap — matches the other two Filament TextureView renderers'
        // frame pacing philosophy in this same screen.
        private const val FRAME_PERIOD_MS = 16L
    }
}
