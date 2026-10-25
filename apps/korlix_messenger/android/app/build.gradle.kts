import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Push remains explicitly unconfigured in ordinary CI/developer builds. A
// Firebase Android client file enables only the native messaging source set.
val korlixFcmConfigured = file("google-services.json").isFile
if (korlixFcmConfigured) apply(plugin = "com.google.gms.google-services")

// KORLIX_MESSENGER_ANDROID_RELEASE_SIGNING_REPAIR_BEGIN
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
    "KORLIX_MESSENGER_ANDROID_STORE_FILE"
)
val korlixAndroidReleaseStorePassword = korlixAndroidKeyProp(
    "storePassword",
    "KORLIX_MESSENGER_ANDROID_STORE_PASSWORD"
)
val korlixAndroidReleaseKeyAlias = korlixAndroidKeyProp(
    "keyAlias",
    "KORLIX_MESSENGER_ANDROID_KEY_ALIAS"
)
val korlixAndroidReleaseKeyPassword = korlixAndroidKeyProp(
    "keyPassword",
    "KORLIX_MESSENGER_ANDROID_KEY_PASSWORD"
)

fun korlixAndroidSigningFileOrNull(configuredPath: String): java.io.File? {
    val candidates = listOf(
        configuredPath,
        "app/messenger-release-key.jks",
        "messenger-release-key.jks"
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

// KORLIX_MESSENGER_ANDROID_RELEASE_SIGNING_REPAIR_END

android {
    namespace = "com.korlixdeveloper.messenger"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.korlixdeveloper.messenger"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["korlixFcmEnabled"] = korlixFcmConfigured.toString()
    }

    sourceSets.getByName("main").java.srcDir(
        if (korlixFcmConfigured) "src/fcm/kotlin" else "src/noFcm/kotlin"
    )

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
    if (korlixFcmConfigured) {
        implementation(platform("com.google.firebase:firebase-bom:34.19.0"))
        implementation("com.google.firebase:firebase-messaging")
    }
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
                "KORLIX_MESSENGER_ANDROID_STORE_FILE/STORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD environment variables."
        )
    }
}

flutter { source = "../.." }
