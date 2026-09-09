package com.tahafayyaz.twin_ar.roomar

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.core.content.ContextCompat
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableApkTooOldException
import com.google.ar.core.exceptions.UnavailableArcoreNotInstalledException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableSdkTooOldException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import io.flutter.plugin.platform.PlatformView

/**
 * TWin AR — Phase 9.2 R6 Tier-1 markerless-ARCore PlatformView.
 *
 * Composes the real ARCore camera + plane/reticle GL layer
 * ([RoomArCoreRenderer], bottom) with the transparent Filament product overlay
 * ([RoomArCoreModelRenderer], top) — the same two-layer TextureView-over-
 * camera composition already proven for Tier 2. Owns the [Session]'s
 * lifecycle (construction / resume / pause / close) on the **main thread**,
 * per ARCore's own contract; the GL thread only ever calls `session.update()`.
 *
 * All gesture recognition (tap-to-place position, drag-to-reposition,
 * two-finger rotate) happens in Flutter — exactly like Tier 2/3 — and reaches
 * this class as plain method calls with **normalized** (0..1) view-fraction
 * coordinates, so no device-pixel-ratio conversion is needed on either side.
 */
class RoomArCoreView(
    private val context: Context,
    @Suppress("unused") private val viewId: Int,
    initialMode: String = "chair",
) : PlatformView {

    private val tag = "RoomArCoreView"
    private val main = Handler(Looper.getMainLooper())

    private val glRenderer = RoomArCoreRenderer(context, RendererListener())

    /** A separate, non-anonymous-inline listener class — referencing
     *  [glRenderer] from a lambda passed into [glRenderer]'s own constructor
     *  is a circular initializer Kotlin cannot type-check. This class needs
     *  no such reference: everything it needs arrives as call parameters. */
    private inner class RendererListener : RoomArCoreRenderer.Listener {
        override fun onFrame(
            state: RoomArCoreFrameState,
            anchorPoseMatrix: FloatArray?,
            initialYawDegrees: Float?,
        ) {
            modelRenderer?.updateAnchorPose(anchorPoseMatrix)
            // Only set on the exact frame a *new* placement happens (never a
            // reposition) — see RoomArCoreRenderer.faceCameraYawDegrees's doc
            // comment. A reposition-drag must keep whatever yaw the customer
            // already dialled in, so this is applied, not unconditionally.
            if (initialYawDegrees != null) modelRenderer?.yawDegrees = initialYawDegrees
            main.post {
                if (!disposed) RoomArCorePlugin.emitFrame(state)
            }
        }

        override fun onCameraPose(viewMatrix: FloatArray, projectionMatrix: FloatArray) {
            modelRenderer?.updateCameraPose(viewMatrix, projectionMatrix)
        }
    }

    // TextureView-hosted (not GLSurfaceView) — see RoomArCoreGlHost's doc
    // comment for why: a raw SurfaceView-backed GLSurfaceView embedded in a
    // Flutter AndroidView rendered correctly but never received touch
    // events (tracker §26).
    private val glHost = RoomArCoreGlHost(context, glRenderer)

    private val modelRenderer: RoomArCoreModelRenderer? =
        runCatching { RoomArCoreModelRenderer(context, initialMode) }
            .onFailure { Log.e(tag, "RoomArCoreModelRenderer init failed", it) }
            .getOrNull()

    private val root = FrameLayout(context).apply {
        addView(
            glHost.textureView,
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

    private var session: Session? = null
    private var installRequested = false
    private var disposed = false
    private var resumed = false

    /** "chair"/"table"/"lamp"/"sofa" -> that product's Filament model, or the
     *  live Firestore product id for every other product (no bundled asset —
     *  see [RoomArCoreModelRenderer.bundledFor]). */
    fun setArMode(mode: String) { modelRenderer?.select(mode) }

    fun setExternalModel(mode: String, path: String?) {
        modelRenderer?.setExternalModel(mode, path)
    }

    /** [fx]/[fy] normalized (0..1) position within this view — Flutter already
     *  did the gesture recognition; this class only forwards the real
     *  ARCore hit-test + anchor request. */
    fun placeAt(fx: Double, fy: Double) {
        val x = (fx * glRenderer.viewportWidth).toFloat()
        val y = (fy * glRenderer.viewportHeight).toFloat()
        glRenderer.queueTap(x, y)
    }

    fun beginReposition() { glRenderer.dragging = true }

    fun repositionTo(fx: Double, fy: Double) {
        val x = (fx * glRenderer.viewportWidth).toFloat()
        val y = (fy * glRenderer.viewportHeight).toFloat()
        glRenderer.queueTap(x, y)
    }

    fun endReposition() { glRenderer.dragging = false }

    fun setYaw(degrees: Double) { modelRenderer?.yawDegrees = degrees.toFloat() }

    fun resetPlacement() {
        glRenderer.clearAnchor()
        modelRenderer?.updateAnchorPose(null)
        modelRenderer?.resetYaw()
    }

    fun setActive(active: Boolean) {
        if (disposed) return
        if (active) resume() else pause()
    }

    init {
        RoomArCorePlugin.activeView = this
        modelRenderer?.start()
        maybeCreateAndResumeSession()
    }

    /**
     * Creates the [Session] (if not already created) and resumes it. Handles
     * every documented ARCore failure honestly:
     *  - not installed / APK too old -> requests the Play Store install flow
     *    (main thread, requires an [Activity] — this class's `context` is the
     *    Flutter embedding Activity); the customer returning to this screen
     *    (or the app's normal resume -> [setActive] wiring) retries this same
     *    method, so a successful install is picked up without a crash or a
     *    stuck screen.
     *  - device genuinely incapable / user declined / SDK too old -> a
     *    terminal "arcore-unavailable" event, so the Dart ViewModel can fall
     *    back to Tier 2/3 exactly like the existing camera-permission /
     *    engine-unavailable fallback screens.
     *  - camera permission missing -> a terminal "camera-permission" event
     *    (the prep screen is expected to have already secured this, so this
     *    is defence-in-depth, mirroring Tier 2's own check).
     */
    private fun maybeCreateAndResumeSession() {
        if (disposed) return
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            emitTerminal("camera-permission", "Camera permission not granted")
            return
        }

        var localSession = session
        if (localSession == null) {
            try {
                val activity = context as? Activity
                if (activity != null) {
                    when (ArCoreApk.getInstance().requestInstall(activity, !installRequested)) {
                        ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                            installRequested = true
                            emitTerminal(
                                "arcore-installing",
                                "Finishing ARCore setup — please try again once it completes",
                            )
                            return
                        }
                        ArCoreApk.InstallStatus.INSTALLED -> { /* fall through */ }
                    }
                }
                localSession = Session(context)
                val config = Config(localSession).apply {
                    planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                    lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
                    focusMode = Config.FocusMode.AUTO
                    updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                }
                localSession.configure(config)
                session = localSession
            } catch (e: UnavailableArcoreNotInstalledException) {
                Log.w(tag, "ARCore not installed", e)
                emitTerminal("arcore-unavailable", "ARCore is not installed on this device")
                return
            } catch (e: UnavailableUserDeclinedInstallationException) {
                Log.w(tag, "ARCore install declined", e)
                emitTerminal("arcore-unavailable", "ARCore installation was declined")
                return
            } catch (e: UnavailableApkTooOldException) {
                Log.w(tag, "ARCore APK too old", e)
                emitTerminal("arcore-unavailable", "ARCore needs to be updated")
                return
            } catch (e: UnavailableSdkTooOldException) {
                Log.w(tag, "app's ARCore SDK too old", e)
                emitTerminal("arcore-unavailable", "This app needs to be updated for AR")
                return
            } catch (e: UnavailableDeviceNotCompatibleException) {
                Log.w(tag, "device not ARCore-compatible", e)
                emitTerminal("arcore-unavailable", "This device does not support AR")
                return
            } catch (e: Throwable) {
                Log.e(tag, "session creation failed", e)
                emitTerminal("arcore-unavailable", e.message ?: "AR could not start")
                return
            }
        }

        try {
            localSession.resume()
            glRenderer.session = localSession
            resumed = true
        } catch (e: CameraNotAvailableException) {
            Log.e(tag, "camera not available", e)
            emitTerminal("camera-unavailable", "The camera is in use by another app")
        }
    }

    private fun resume() {
        modelRenderer?.start()
        // ARCore's own contract: resume the Session BEFORE the render host
        // starts pulling frames again — `glRenderer.session` must already be
        // a resumed Session by the time the render thread's next
        // `onDrawFrame` runs, or it hits ARCore's own "session not resumed"
        // exception on the very first frame after backgrounding (caught, so
        // not a crash, but an avoidable flash of an error frame).
        maybeCreateAndResumeSession()
        glHost.resume()
    }

    private fun pause() {
        if (resumed) {
            session?.pause()
            resumed = false
        }
        glHost.pause()
        modelRenderer?.stop()
    }

    private fun emitTerminal(state: String, message: String) {
        main.post {
            if (!disposed) RoomArCorePlugin.emitTerminal(state, message)
        }
    }

    override fun getView(): View = root

    override fun dispose() {
        disposed = true
        if (RoomArCorePlugin.activeView === this) RoomArCorePlugin.activeView = null
        if (resumed) {
            runCatching { session?.pause() }
            resumed = false
        }
        runCatching { glHost.destroy() }
            .onFailure { Log.w(tag, "gl host destroy", it) }
        runCatching { modelRenderer?.destroy() }
            .onFailure { Log.w(tag, "model renderer destroy", it) }
        runCatching { session?.close() }
            .onFailure { Log.w(tag, "session close", it) }
        session = null
    }
}
