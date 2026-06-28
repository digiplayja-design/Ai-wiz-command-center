allprojects {
    repositories {
        google()
        mavenCentral()
    }
    configurations.all {
        resolutionStrategy {
            force("androidx.work:work-runtime:2.9.0")
            force("androidx.work:work-runtime-ktx:2.9.0")
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Korlix Android parity: force all Android modules/plugins to compile against API 36.
subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.gradle.BaseExtension>("android") {
            compileSdkVersion(36)
        }
    }
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.BaseExtension>("android") {
            compileSdkVersion(36)
        }
    }
}

// KORLIX_FORCE_ANDROID_COMPILE_SDK_36_BEGIN
// Force app and Flutter plugin subprojects, including passkeys_doctor, to compile against API 36.
subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.gradle.BaseExtension>("android") {
            compileSdkVersion(36)
        }
    }

    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.BaseExtension>("android") {
            compileSdkVersion(36)
        }
    }
}
// KORLIX_FORCE_ANDROID_COMPILE_SDK_36_END
