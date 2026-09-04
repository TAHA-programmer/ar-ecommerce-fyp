package com.tahafayyaz.twin_ar

import com.tahafayyaz.twin_ar.roomar.RoomArCapabilitiesPlugin
import com.tahafayyaz.twin_ar.roomar.RoomArMarkerPlugin
import com.tahafayyaz.twin_ar.roomar.RoomArPreviewPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// flutter_stripe requires the host Activity to be a FlutterFragmentActivity
// (PaymentSheet is shown from a FragmentManager). No Flutter/business logic
// change - navigation and appearance are unaffected.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Phase 9.2 R5 — Tier-2 Marker-AR (CameraX + OpenCV ArUco + Filament),
        // exposed to Flutter over the twin_ar/room_ar/marker/* channels. Camera
        // is opened lazily by the PlatformView only when the AR screen mounts.
        RoomArMarkerPlugin.register(flutterEngine)
        // Phase 9.2 R7 — Tier-3 Interactive 3D Preview (Filament orbit viewer,
        // no camera) over twin_ar/room_ar/preview/*.
        RoomArPreviewPlugin.register(flutterEngine)
        // Phase 9.2 R8 — device-capability probe for tier routing.
        RoomArCapabilitiesPlugin.register(flutterEngine, applicationContext)
    }
}
