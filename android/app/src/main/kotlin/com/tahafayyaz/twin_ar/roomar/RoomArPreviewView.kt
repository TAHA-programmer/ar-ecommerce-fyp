package com.tahafayyaz.twin_ar.roomar

import android.content.Context
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.plugin.platform.PlatformView

/**
 * TWin AR — Phase 9.2 R7 Tier-3 Interactive 3D Preview PlatformView.
 *
 * A single transparent Filament [TextureView] ([RoomArPreviewRenderer]) — no
 * camera, no marker. Gesture math (orbit / pan / pinch-zoom / reset) is done on
 * the Flutter side and forwarded here as deltas, exactly as the Tier-2 screen
 * feeds placement math to its renderer.
 *
 * Registered / driven via [RoomArPreviewPlugin].
 */
class RoomArPreviewView(
    context: Context,
    @Suppress("unused") private val viewId: Int,
    initialMode: String,
    initialPath: String? = null,
) : PlatformView {

    private val tag = "RoomArPreviewView"

    private val renderer: RoomArPreviewRenderer? =
        runCatching { RoomArPreviewRenderer(context, initialMode, initialPath) }
            .onFailure { Log.e(tag, "RoomArPreviewRenderer init failed", it) }
            .getOrNull()

    private val root = FrameLayout(context).apply {
        renderer?.let {
            addView(
                it.textureView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
        }
    }

    private var disposed = false

    init {
        RoomArPreviewPlugin.activeView = this
        renderer?.onLoadState = { RoomArPreviewPlugin.emitLoadState(it) }
        if (renderer == null) {
            RoomArPreviewPlugin.emitLoadState("failed")
        } else {
            renderer.start()
        }
    }

    fun setModel(mode: String, path: String?) {
        if (path == null) renderer?.select(mode) else renderer?.setExternalModel(mode, path)
    }

    fun orbit(dx: Double, dy: Double) = renderer?.orbit(dx, dy) ?: Unit
    fun pan(dx: Double, dy: Double) = renderer?.pan(dx, dy) ?: Unit
    fun zoom(scale: Double) = renderer?.zoom(scale) ?: Unit
    fun resetView() = renderer?.reset() ?: Unit

    fun setActive(active: Boolean) {
        if (disposed) return
        if (active) renderer?.start() else renderer?.stop()
    }

    override fun getView(): View = root

    override fun dispose() {
        disposed = true
        if (RoomArPreviewPlugin.activeView === this) RoomArPreviewPlugin.activeView = null
        runCatching { renderer?.destroy() }
            .onFailure { Log.w(tag, "renderer destroy", it) }
    }
}
