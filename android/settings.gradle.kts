pluginManagement {
    plugins {
        id("com.android.application") version "8.9.2"
        id("org.jetbrains.kotlin.android") version "2.2.10"
        id("org.jetbrains.kotlin.jvm") version "2.2.10"
        id("org.jetbrains.kotlin.plugin.compose") version "2.2.10"
    }
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "AI Fitness"

if (!providers.gradleProperty("contractOnly").isPresent) include(":app")

include(":consumer")
