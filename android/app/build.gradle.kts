plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tahafayyaz.twin_ar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tahafayyaz.twin_ar"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Phase 9.2 R6 — Tier-1 ARCore requires API 24+ (`com.google.ar:core`'s
        // own manifest declares minSdkVersion 24; Gradle's manifest merge fails
        // if the app's minSdk is lower). Coerced up from Flutter's own default
        // rather than silently relying on it — ARCore is declared `optional`
        // (see AndroidManifest.xml), so a device below API 24 simply never sees
        // Tier 1, exactly like a device with no camera never sees Tier 2.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Phase 8.13.5: keep Flutter's default R8 config and add our own
            // rules so the release build tolerates the excluded Stripe
            // push-provisioning classes (see proguard-rules.pro).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Phase 8.13.5: lint-vital tries to resolve every release dependency,
    // including the unresolvable play-services-tapandpay pulled in by the
    // excluded push-provisioning module. This app has no release lint gate.
    lint {
        checkReleaseBuilds = false
    }
}

// Phase 8.13.5: flutter_stripe 14 transitively adds Stripe's card-issuing
// "push provisioning" SDK, which this app does not use. Its transitive
// dependency com.google.android.gms:play-services-tapandpay is only published
// to a Google-restricted Maven repo, breaking release dependency resolution
// and R8. Drop the module everywhere; PaymentSheet does not need it.
configurations.all {
    exclude(group = "com.stripe", module = "stripe-android-issuing-push-provisioning")
}

// Phase 9.2 R5 — Tier-2 Marker-AR (OpenCV ArUco + CameraX + Filament). Ported
// from the physically-approved `_marker_ar_poc`; versions pinned to exactly what
// that PoC built and ran with on this toolchain (AGP 9.0.1 / Gradle 9.1 /
// Kotlin 2.3.20 / JVM 17). These pull native .so per ABI — the arm64 release
// grows ~7 MB. No ARCore.
dependencies {
    // OpenCV 4.12 Java + native — org.opencv.objdetect.ArucoDetector + Calib3d.solvePnP.
    implementation("org.opencv:opencv:4.12.0")

    // CameraX — one camera, Preview + ImageAnalysis on the same stream.
    val camerax = "1.4.2"
    implementation("androidx.camera:camera-core:$camerax")
    implementation("androidx.camera:camera-camera2:$camerax")
    implementation("androidx.camera:camera-lifecycle:$camerax")
    implementation("androidx.camera:camera-view:$camerax")

    // Filament — real-time PBR renderer for the transparent model overlay.
    // Version matches what ar_flutter_plugin_plus 1.1.3 pulls (spike-verified).
    val filament = "1.68.4"
    implementation("com.google.android.filament:filament-android:$filament")
    implementation("com.google.android.filament:gltfio-android:$filament")
    implementation("com.google.android.filament:filament-utils-android:$filament")

    // Phase 9.2 R6 — Tier-1 markerless ARCore. Google's own SDK, no
    // third-party AR wrapper (Sceneform is deprecated; the project already
    // hand-rolls Filament directly for Tier 2/3, so Tier 1 follows the same
    // pattern: ARCore owns tracking/plane-detection/hit-test/anchors via its
    // own GLSurfaceView camera passthrough, and the existing Filament
    // pipeline renders only the transparent product overlay on top, driven
    // every frame by the ARCore camera + anchor pose — no new rendering
    // abstraction, no custom Filament material/matc build step).
    implementation("com.google.ar:core:1.49.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
