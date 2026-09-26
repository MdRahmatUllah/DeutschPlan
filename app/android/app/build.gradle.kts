import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // X1's Glance widget (#160); Glance itself comes with home_widget.
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// #170: the owner's upload key, from android/key.properties when it is there
// (docs/05-dev-guide/release.md). Without it a release build is signed with
// the debug key, so `flutter build` and the device checks still work; Play
// refuses a debug-signed upload, so nothing reaches it signed wrongly.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

android {
    // The owner's (#170): it can never change once the app is on Play.
    namespace = "io.github.rahmatullah.deutschplan"
    // permission_handler_android requires API 37 or later to compile against.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs java.time on older API levels.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "io.github.rahmatullah.deutschplan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // docs/01-architecture/tech-stack.md: Android 8.0+ (API 26), targetSdk latest.
        minSdk = 26
        targetSdk = 37
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        compose = true
    }

    signingConfigs {
        if (!keyProperties.isEmpty) {
            create("upload") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (keyProperties.isEmpty) "debug" else "upload",
            )
            // The plugins' native libraries' symbol tables ride in the bundle,
            // so Play symbolicates their crashes (#170). Dart's own come from
            // `--split-debug-info`, kept with each release.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
