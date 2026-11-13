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

// Some Flutter plugins (including passkeys_doctor) set compileSdk after applying
// the Android plugin. Apply the API 36 floor once their android DSL is complete.
// Register these hooks before evaluationDependsOn eagerly evaluates :app.
subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.api.variant.ApplicationAndroidComponentsExtension>("androidComponents") {
            finalizeDsl { android ->
                android.compileSdk = maxOf(android.compileSdk ?: 0, 36)
            }
        }
    }
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension>("androidComponents") {
            finalizeDsl { android ->
                android.compileSdk = maxOf(android.compileSdk ?: 0, 36)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
