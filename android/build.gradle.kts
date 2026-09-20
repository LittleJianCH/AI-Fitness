// Share one Kotlin plugin classloader across the native app and JVM consumer.
plugins {
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.jvm") apply false
    id("org.jetbrains.kotlin.android") apply false
    id("org.jetbrains.kotlin.plugin.compose") apply false
}

// Plugin versions are pinned in settings.gradle.kts.
// The formatter runs only as a build tool; it is never an app runtime dependency.
val ktfmt by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
    attributes {
        attribute(Usage.USAGE_ATTRIBUTE, objects.named(Usage.JAVA_RUNTIME))
        attribute(Bundling.BUNDLING_ATTRIBUTE, objects.named(Bundling.SHADOWED))
    }
    resolutionStrategy.activateDependencyLocking()
}

dependencies { add(ktfmt.name, "com.facebook:ktfmt:0.64") }

val maintainedKotlin =
    fileTree(projectDir) {
        include("app/src/**/*.kt", "consumer/src/**/*.kt")
        include("*.gradle.kts", "app/*.gradle.kts", "consumer/*.gradle.kts")
        exclude("**/generated/**", "**/build/**")
    }

fun registerFormatter(name: String, checkOnly: Boolean) =
    tasks.register<JavaExec>(name) {
        group = if (checkOnly) "verification" else "formatting"
        description =
            if (checkOnly) "Parse/check all maintained Kotlin, including Compose, without an SDK."
            else "Format all maintained Kotlin using the pinned ktfmt Kotlin style."
        classpath = ktfmt
        mainClass.set("com.facebook.ktfmt.cli.Main")
        inputs.files(maintainedKotlin)
        doFirst {
            val sources = maintainedKotlin.files.sortedBy { it.path }
            check(sources.isNotEmpty())
            logger.lifecycle(
                "ktfmt: ${sources.size} maintained Kotlin source/build files (generated/build excluded)"
            )
            args =
                listOf("--kotlinlang-style") +
                    (if (checkOnly) listOf("--dry-run", "--set-exit-if-changed") else emptyList()) +
                    sources.map { it.absolutePath }
        }
    }

registerFormatter("formatKotlin", false)

registerFormatter("checkKotlinFormat", true)

val checkLocalization by
    tasks.registering(Exec::class) {
        group = "verification"
        description = "Check English and Simplified Chinese catalog completeness and arguments."
        inputs.file("check_localization.py")
        inputs.dir("app/src/main/res")
        inputs.dir("app/src/main/java")
        commandLine("python3", file("check_localization.py"))
    }

tasks.named("checkKotlinFormat") { dependsOn(checkLocalization) }
