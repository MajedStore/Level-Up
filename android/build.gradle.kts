buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.21")
    }
}

plugins {
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.21" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // home_widget declares dynamic versions. Apply the app's existing stable
    // Glance choice to library variants too, including release AAR/lint checks.
    configurations.configureEach {
        resolutionStrategy {
            force("androidx.glance:glance-appwidget:1.1.1")
            force("androidx.glance:glance-material3:1.1.1")
            force("androidx.work:work-runtime:2.9.1")
            force("androidx.work:work-runtime-ktx:2.9.1")
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

subprojects {
    val alignJvm: Project.() -> Unit = {
        // Secure storage 10.x uses Java 17 language features. Preserve its
        // declared target instead of downgrading it with the legacy plugins.
        val javaTarget = if (name == "flutter_secure_storage") JavaVersion.VERSION_17 else JavaVersion.VERSION_11
        val kotlinTarget = if (javaTarget == JavaVersion.VERSION_17) org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 else org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.compileOptions {
                sourceCompatibility = javaTarget
                targetCompatibility = javaTarget
            }
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = javaTarget.toString(); targetCompatibility = javaTarget.toString()
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions { jvmTarget.set(kotlinTarget) }
        }
    }
    if (state.executed) alignJvm() else afterEvaluate { alignJvm() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
