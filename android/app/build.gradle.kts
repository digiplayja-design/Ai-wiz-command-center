import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun korlixSigningFileOrNull(value: Any?): java.io.File? {
    val path = value?.toString()?.trim().orEmpty()
    if (path.isEmpty()) {
        return null
    }

    return rootProject.file(path)
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

println("Korlix Android release signing complete: $korlixAndroidHasReleaseSigning")
// KORLIX_ANDROID_RELEASE_SIGNING_REPAIR_END

android {
    
    
    compileSdk = 36
compileSdk = 36
namespace = "com.korlixdeveloper.korlixai"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.korlixdeveloper.korlixai"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = korlixSigningFileOrNull(keystoreProperties.getProperty("storeFile") ?: "")
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
        }
    }


    // KORLIX_ANDROID_RELEASE_SIGNING_OVERRIDE_BEGIN
    signingConfigs {
        val releaseSigning = findByName("release") ?: create("release")
        releaseSigning.storeFile = korlixAndroidReleaseStoreFile
        releaseSigning.storePassword = korlixAndroidReleaseStorePassword
        releaseSigning.keyAlias = korlixAndroidReleaseKeyAlias
        releaseSigning.keyPassword = korlixAndroidReleaseKeyPassword
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (korlixAndroidHasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
    // KORLIX_ANDROID_RELEASE_SIGNING_OVERRIDE_END
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}
