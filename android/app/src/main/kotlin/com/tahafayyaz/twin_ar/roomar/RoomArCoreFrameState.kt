package com.tahafayyaz.twin_ar.roomar

import com.google.ar.core.Camera

/**
 * TWin AR — Phase 9.2 R6 Tier-1 ARCore per-frame state, handed from the GL
 * thread ([RoomArCoreRenderer]) to Flutter (via [RoomArCorePlugin]'s event
 * channel, posted to the main thread first). Deliberately a plain data
 * holder — no business logic, mirroring [RoomArMarkerView]'s frame payload.
 */
data class RoomArCoreFrameState(
    val tracking: Boolean,
    val trackingFailureReason: String,
    val planesFound: Boolean,
    val hasAnchor: Boolean,
    val anchorTracking: Boolean,
    val justPlaced: Boolean,
    val reticleVisible: Boolean,
    val error: String? = null,
    /** `true` for exactly the one frame a queued tap was processed and
     *  [RoomArCoreRenderer.validHit] rejected every raw hit (customer
     *  requirement: "invalid ARCore hits must produce honest visible
     *  feedback instead of silently doing nothing" — tracker §32). Never
     *  persists past that single frame. */
    val tapRejected: Boolean = false,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "tracking" to tracking,
        "trackingFailureReason" to trackingFailureReason,
        "planesFound" to planesFound,
        "hasAnchor" to hasAnchor,
        "anchorTracking" to anchorTracking,
        "justPlaced" to justPlaced,
        "reticleVisible" to reticleVisible,
        "error" to error,
        "tapRejected" to tapRejected,
    )

    companion object {
        fun cameraUnavailable() = RoomArCoreFrameState(
            tracking = false,
            trackingFailureReason = "CAMERA_UNAVAILABLE",
            planesFound = false,
            hasAnchor = false,
            anchorTracking = false,
            justPlaced = false,
            reticleVisible = false,
            error = "Camera became unavailable",
        )

        fun error(message: String) = RoomArCoreFrameState(
            tracking = false,
            trackingFailureReason = "NONE",
            planesFound = false,
            hasAnchor = false,
            anchorTracking = false,
            justPlaced = false,
            reticleVisible = false,
            error = message,
        )

        /** [reason] textual form of `Camera.TrackingFailureReason` — never `null`
         *  in ARCore's own API, but guarded anyway. */
        fun failureReasonName(camera: Camera): String =
            runCatching { camera.trackingFailureReason.name }.getOrDefault("NONE")
    }
}
