import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val magicKeys = Properties()
val magicKeyFile = rootProject.file("key.properties")
if (magicKeyFile.exists()) magicKeyFile.inputStream().use { magicKeys.load(it) }
val magicStore = magicKeys.getProperty("storeFile") ?: System.getenv("KORLIX_MAGIC_ANDROID_STORE_FILE")
val magicStorePassword = magicKeys.getProperty("storePassword") ?: System.getenv("KORLIX_MAGIC_ANDROID_STORE_PASSWORD")
val magicKeyAlias = magicKeys.getProperty("keyAlias") ?: System.getenv("KORLIX_MAGIC_ANDROID_KEY_ALIAS")
val magicKeyPassword = magicKeys.getProperty("keyPassword") ?: System.getenv("KORLIX_MAGIC_ANDROID_KEY_PASSWORD")
val magicSigningReady = listOf(magicStore, magicStorePassword, magicKeyAlias, magicKeyPassword).all { !it.isNullOrBlank() }

android {
    namespace = "com.korlixdeveloper.magiccamera"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.korlixdeveloper.magiccamera"
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
        if (magicSigningReady) {
            create("magicRelease") {
                storeFile = file(magicStore!!)
                storePassword = magicStorePassword
                keyAlias = magicKeyAlias
                keyPassword = magicKeyPassword
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("magicRelease")
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

// A store candidate must never fall back to the debug signing identity.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name == "bundleRelease" || it.name == "assembleRelease" } && !magicSigningReady) {
        throw GradleException("Configure all four Magic Camera release signing values in android/key.properties or the dedicated KORLIX_MAGIC_ANDROID environment variables.")
    }
}
