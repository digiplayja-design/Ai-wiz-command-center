import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// KORLIX_ANDROID_RELEASE_SIGNING_REPAIR_BEGIN
val korlixAndroidKeyProperties = Properties()
val korlixAndroidKeyPropertiesFile = rootProject.file("key.properties")

if (korlixAndroidKeyPropertiesFile.exists()) {
    korlixAndroidKeyProperties.load(FileInputStream(korlixAndroidKeyPropertiesFile))
}

fun korlixAndroidKeyProp(name: String, vararg envNames: String): String {
    val fileValue = korlixAndroidKeyProperties.getProperty(name)?.trim().orEmpty()

    if (fileValue.isNotEmpty()) {
        return fileValue
    }

    for (envName in envNames) {
        val envValue = System.getenv(envName)?.trim().orEmpty()

        if (envValue.isNotEmpty()) {
            return envValue
        }
    }

    return ""
}

val korlixAndroidReleaseStoreFilePath = korlixAndroidKeyProp(
    "storeFile",
    "KORLIX_ANDROID_STORE_FILE",
    "ANDROID_KEYSTORE_PATH",
    "CM_KEYSTORE_PATH"
)
val korlixAndroidReleaseStorePassword = korlixAndroidKeyProp(
    "storePassword",
    "KORLIX_ANDROID_STORE_PASSWORD",
    "ANDROID_KEYSTORE_PASSWORD",
    "CM_KEYSTORE_PASSWORD"
)
val korlixAndroidReleaseKeyAlias = korlixAndroidKeyProp(
    "keyAlias",
    "KORLIX_ANDROID_KEY_ALIAS",
    "ANDROID_KEY_ALIAS",
    "CM_KEY_ALIAS"
)
val korlixAndroidReleaseKeyPassword = korlixAndroidKeyProp(
    "keyPassword",
    "KORLIX_ANDROID_KEY_PASSWORD",
    "ANDROID_KEY_PASSWORD",
    "CM_KEY_PASSWORD"
)

fun korlixAndroidSigningFileOrNull(configuredPath: String): java.io.File? {
    val candidates = listOf(
        configuredPath,
        "app/korlix-release-key.jks",
        "korlix-release-key.jks"
    ).map { it.trim() }.filter { it.isNotEmpty() }

    return candidates
        .map { rootProject.file(it) }
        .firstOrNull { it.exists() && it.isFile }
}

val korlixAndroidReleaseStoreFile = korlixAndroidSigningFileOrNull(
    korlixAndroidReleaseStoreFilePath
)

val korlixAndroidHasReleaseSigning =
    korlixAndroidReleaseStoreFile != null &&
        korlixAndroidReleaseStorePassword.isNotBlank() &&
        korlixAndroidReleaseKeyAlias.isNotBlank() &&
        korlixAndroidReleaseKeyPassword.isNotBlank()

// KORLIX_ANDROID_RELEASE_SIGNING_REPAIR_END

android {
    namespace = "com.korlixdeveloper.korlixai"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.korlixdeveloper.korlixai"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = korlixAndroidReleaseStoreFile
            storePassword = korlixAndroidReleaseStorePassword
            keyAlias = korlixAndroidReleaseKeyAlias
            keyPassword = korlixAndroidReleaseKeyPassword
        }
    }

    buildTypes {
        getByName("release") {
            // Never produce a release artifact signed with the public debug key.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("com.google.android.play:review:2.0.2")
}

// Fail at the release task boundary, without blocking debug builds or analysis.
gradle.taskGraph.whenReady {
    val buildsReleaseArtifact = allTasks.any {
        it.project == project && it.name in setOf(
            "assembleRelease", "bundleRelease", "packageRelease"
        )
    }
    if (buildsReleaseArtifact && !korlixAndroidHasReleaseSigning) {
        throw GradleException(
            "Release signing is required. Configure key.properties or the " +
                "KORLIX_ANDROID_STORE_FILE/STORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD environment variables."
        )
    }
}
