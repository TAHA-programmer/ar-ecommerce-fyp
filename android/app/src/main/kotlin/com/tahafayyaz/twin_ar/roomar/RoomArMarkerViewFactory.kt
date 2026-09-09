package com.tahafayyaz.twin_ar.roomar

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class RoomArMarkerViewFactory(
    @Suppress("unused") private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // `mode` creation param — the native renderer slot key (chair/table/
        // lamp/sofa for a bundled product, or the live Firestore product id
        // otherwise). Selected synchronously during construction so a product
        // with no bundled counterpart renders nothing until its verified GLB
        // arrives, instead of hard-defaulting to the chair. See
        // RoomArModelRenderer's `initialMode`. Mirrors RoomArCoreViewFactory.
        val mode = (args as? Map<*, *>)?.get("mode") as? String ?: "chair"
        return RoomArMarkerView(context, viewId, mode)
    }
}
