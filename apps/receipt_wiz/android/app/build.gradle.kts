import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val receiptKeys = Properties()
val receiptKeyFile = rootProject.file("key.properties")
if (receiptKeyFile.exists()) receiptKeyFile.inputStream().use { receiptKeys.load(it) }
val receiptStore = receiptKeys.getProperty("storeFile") ?: System.getenv("CM_KEYSTORE_PATH")

android {
    namespace = "com.korlixdeveloper.receiptwiz"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.korlixdeveloper.receiptwiz"
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

    signingConfigs {
        if (!receiptStore.isNullOrBlank()) {
            create("receiptRelease") {
                storeFile = file(receiptStore)
                storePassword = receiptKeys.getProperty("storePassword") ?: System.getenv("CM_KEYSTORE_PASSWORD")
                keyAlias = receiptKeys.getProperty("keyAlias") ?: System.getenv("CM_KEY_ALIAS")
                keyPassword = receiptKeys.getProperty("keyPassword") ?: System.getenv("CM_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("receiptRelease")
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

// Store builds require the Receipt Wiz signing configuration.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name == "bundleRelease" || it.name == "assembleRelease" } && receiptStore.isNullOrBlank()) {
        throw GradleException("Configure the Receipt Wiz release keystore in android/key.properties or Codemagic before building a release.")
    }
}
