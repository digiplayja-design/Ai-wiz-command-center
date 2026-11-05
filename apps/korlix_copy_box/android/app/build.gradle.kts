import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Copy Box has an independent application ID and signing configuration.
// Never fall back to another KORLIX app's signing environment variables.
val copyBoxKeys = Properties()
val copyBoxKeyFile = rootProject.file("key.properties")
if (copyBoxKeyFile.exists()) {
    copyBoxKeyFile.inputStream().use { copyBoxKeys.load(it) }
}
fun copyBoxSigningValue(property: String, environment: String): String? =
    copyBoxKeys.getProperty(property)?.takeIf { it.isNotBlank() }
        ?: System.getenv(environment)?.takeIf { it.isNotBlank() }
val copyBoxStore = copyBoxSigningValue("storeFile", "KORLIX_COPYBOX_ANDROID_STORE_FILE")
val copyBoxStorePassword = copyBoxSigningValue("storePassword", "KORLIX_COPYBOX_ANDROID_STORE_PASSWORD")
val copyBoxKeyAlias = copyBoxSigningValue("keyAlias", "KORLIX_COPYBOX_ANDROID_KEY_ALIAS")
val copyBoxKeyPassword = copyBoxSigningValue("keyPassword", "KORLIX_COPYBOX_ANDROID_KEY_PASSWORD")
val copyBoxSigningReady = listOf(
    copyBoxStore, copyBoxStorePassword, copyBoxKeyAlias, copyBoxKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.korlixdeveloper.copybox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.korlixdeveloper.copybox"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (copyBoxSigningReady) {
            create("copyBoxRelease") {
                storeFile = file(copyBoxStore!!)
                storePassword = copyBoxStorePassword
                keyAlias = copyBoxKeyAlias
                keyPassword = copyBoxKeyPassword
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("copyBoxRelease")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
flutter { source = "../.." }

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name == "bundleRelease" || it.name == "assembleRelease" }) {
        if (!copyBoxSigningReady) {
            throw GradleException(
                "Configure all four Copy Box signing values in android/key.properties " +
                "or KORLIX_COPYBOX_ANDROID_* environment variables before building a release.",
            )
        }
        if (!file(copyBoxStore!!).isFile) {
            throw GradleException("The configured Copy Box release keystore does not exist.")
        }
    }
}
