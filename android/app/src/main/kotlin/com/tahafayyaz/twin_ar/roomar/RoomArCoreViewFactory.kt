package com.tahafayyaz.twin_ar.roomar

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class RoomArCoreViewFactory(
    @Suppress("unused") private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // `mode` is passed as a creation param (not a post-creation channel
        // call) so the renderer selects the opened product's model
        // synchronously, before anything else can race it — see
        // RoomArCoreModelRenderer's `initialMode` doc comment.
        val mode = (args as? Map<*, *>)?.get("mode") as? String ?: "chair"
        return RoomArCoreView(context, viewId, mode)
    }
}
