plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val eshaSigningKeys = listOf(
    "ESHA_ANDROID_STORE_FILE", "ESHA_ANDROID_STORE_PASSWORD",
    "ESHA_ANDROID_KEY_ALIAS", "ESHA_ANDROID_KEY_PASSWORD",
)
val eshaSigning = eshaSigningKeys.associateWith { System.getenv(it)?.takeIf(String::isNotBlank) }
val eshaSigningConfigured = eshaSigning.values.all { it != null }
require(eshaSigningConfigured || eshaSigning.values.all { it == null }) {
    "Esha release signing requires all four ESHA_ANDROID signing variables."
}

android {
    namespace = "com.korlixdeveloper.esha"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.korlixdeveloper.esha"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (eshaSigningConfigured) {
            create("eshaRelease") {
                storeFile = file(eshaSigning.getValue("ESHA_ANDROID_STORE_FILE")!!)
                storePassword = eshaSigning.getValue("ESHA_ANDROID_STORE_PASSWORD")
                keyAlias = eshaSigning.getValue("ESHA_ANDROID_KEY_ALIAS")
                keyPassword = eshaSigning.getValue("ESHA_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (eshaSigningConfigured) signingConfigs.getByName("eshaRelease") else null
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

dependencies {
    // Bundled model: face landmarks work without downloading a model after installation.
    implementation("com.google.mlkit:face-detection:16.1.7")
}
