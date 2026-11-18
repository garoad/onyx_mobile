plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.onyx.pocket.editor"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.onyx.pocket.editor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val onyxKeystore = System.getenv("ONYX_KEYSTORE_PATH")
    if (onyxKeystore != null) {
        signingConfigs.create("onyxRelease") {
            storeFile = file(onyxKeystore)
            storePassword = System.getenv("ONYX_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ONYX_KEY_ALIAS")
            keyPassword = System.getenv("ONYX_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            // Local APKs are installable; store builds use the publisher's key or an unsigned bundle.
            signingConfig = if (System.getenv("ONYX_UNSIGNED_RELEASE") == "1") null
                else if (onyxKeystore != null) signingConfigs.getByName("onyxRelease")
                else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
