// Compiles only the patched Kotlin files of the TrustTunnel Android engine
// against the original classes.jar (see build.sh). Not part of the app build.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "engine_patch"
