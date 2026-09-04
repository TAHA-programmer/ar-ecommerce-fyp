package com.tahafayyaz.twin_ar.roomar

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class RoomArPreviewViewFactory(
    @Suppress("unused") private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // `mode` (and, for the R16 admin preview, `path`) are passed as creation
        // params so the renderer starts on the correct model immediately — a
        // post-creation `setModel` channel call races the PlatformView's
        // creation and is dropped (`activeView` is still null), which is why
        // every admin preview used to show the chair until "Reset view".
        val map = args as? Map<*, *>
        val mode = map?.get("mode") as? String ?: "chair"
        val path = map?.get("path") as? String
        return RoomArPreviewView(context, viewId, mode, path)
    }
}
