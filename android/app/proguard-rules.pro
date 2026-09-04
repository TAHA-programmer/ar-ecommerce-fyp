# ── Phase 9.2 R5 — Tier-2 Marker-AR native libs (OpenCV / CameraX / Filament) ─
# OpenCV Java classes are bound to native methods via JNI; keep them intact.
-keep class org.opencv.** { *; }
-dontwarn org.opencv.**
# CameraX uses reflection / generated code internally.
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**
# Filament + gltfio bind Java fields/methods from native; keep them all.
-keep class com.google.android.filament.** { *; }
-dontwarn com.google.android.filament.**
# Our own platform-channel surface for the Marker-AR view.
-keep class com.tahafayyaz.twin_ar.roomar.** { *; }

# ── flutter_stripe: unused Issuing / push-provisioning code ──────────────────
# flutter_stripe bundles Stripe's card-issuing "push provisioning" support
# (com.stripe.android.pushProvisioning + com.reactnativestripesdk.pushprovisioning).
# This app only uses PaymentSheet, never Issuing. The feature's transitive
# dependency (com.google.android.gms:play-services-tapandpay) is published only
# to a Google-restricted Maven repo, so it cannot be resolved. The module is
# excluded in build.gradle.kts; tell R8 the resulting dangling references from
# the (still-present) proxy classes are expected and must not fail the build.
-dontwarn com.stripe.android.pushProvisioning.**
-dontwarn com.reactnativestripesdk.pushprovisioning.**
-dontwarn com.google.android.gms.tapandpay.**
