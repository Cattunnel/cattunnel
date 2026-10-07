// Same toolchain as the app (android/settings.gradle) and the serialization
// plugin the upstream lib uses; everything the sources touch is compileOnly -
// the classes come from the original AAR at runtime.
plugins {
    id("com.android.library") version "8.9.1"
    id("org.jetbrains.kotlin.android") version "2.2.10"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.2.10"
}

val originalClasses = file(providers.gradleProperty("originalClassesJar").get())

android {
    namespace = "com.adguard.trusttunnel.patch"
    compileSdk = 35
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    sourceSets["main"].java.srcDir("build/patched-src")
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        // The upstream module name, so the classes fit the rest of the jar.
        moduleName.set("lib_release")
    }
}

dependencies {
    compileOnly(files(originalClasses))
    compileOnly("org.slf4j:slf4j-api:1.7.25")
    compileOnly("io.reactivex.rxjava3:rxandroid:3.0.0")
    compileOnly("com.akuleshov7:ktoml-core:0.7.0")
    compileOnly("androidx.core:core-ktx:1.13.1")
}
