import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val brainSigning = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
fun brainSigningValue(name: String, environment: String): String? =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: brainSigning.getProperty(name)?.takeIf { it.isNotBlank() }
val brainKeystore = brainSigningValue("storeFile", "CM_KEYSTORE_PATH")
val brainStorePassword = brainSigningValue("storePassword", "CM_KEYSTORE_PASSWORD")
val brainKeyAlias = brainSigningValue("keyAlias", "CM_KEY_ALIAS")
val brainKeyPassword = brainSigningValue("keyPassword", "CM_KEY_PASSWORD")
val brainSigningReady = listOf(brainKeystore, brainStorePassword, brainKeyAlias, brainKeyPassword).all { it != null }

android {
    namespace = "com.korlix.brain"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.korlix.brain"
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
        if (brainSigningReady) {
            create("brainRelease") {
                storeFile = file(brainKeystore!!)
                storePassword = brainStorePassword
                keyAlias = brainKeyAlias
                keyPassword = brainKeyPassword
            }
        }
    }
    buildTypes {
        release {
            if (brainSigningReady) signingConfig = signingConfigs.getByName("brainRelease")
        }
    }
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.endsWith("Release") } && !brainSigningReady) {
        throw GradleException("Brain+Voice release signing is missing. Configure the managed upload key in CI; debug signing is not allowed for store builds.")
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
