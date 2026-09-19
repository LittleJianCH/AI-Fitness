plugins { id("org.jetbrains.kotlin.jvm") }

kotlin { jvmToolchain(17) }

sourceSets {
    main {
        kotlin.srcDir("../app/src/main/java")
        kotlin.srcDir(layout.buildDirectory.dir("generated/contract"))
        kotlin.include(
            "**/FitnessApi.kt",
            "**/FitnessViewModel.kt",
            "**/CredentialVault.kt",
            "**/TrainingCalendar.kt",
            "**/WorkoutPresentation.kt",
            "**/contract/**",
        )
    }
    test { kotlin.srcDir("../app/src/test/java") }
}

dependencies {
    implementation("androidx.lifecycle:lifecycle-viewmodel:2.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.json:json:20240303")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
}

val generateContract by
    tasks.registering(Exec::class) {
        inputs.file(rootProject.file("../contracts/build/openapi.json"))
        inputs.file(rootProject.file("../scripts/android_generate"))
        outputs.dir(layout.buildDirectory.dir("generated/contract"))
        commandLine(
            "python3",
            rootProject.file("../scripts/android_generate"),
            "--output",
            layout.buildDirectory
                .file("generated/contract/com/aifitness/contract/Contract.kt")
                .get()
                .asFile,
        )
    }

tasks.named("compileKotlin") { dependsOn(generateContract) }

tasks.test {
    systemProperty("fixtureDir", rootProject.file("../backend/build").absolutePath)
    useJUnit()
    // Connected tests must run every time a disposable server is supplied.
    if (System.getenv("AI_FITNESS_ANDROID_TEST_SERVER") != null) outputs.upToDateWhen { false }
}

dependencyLocking { lockAllConfigurations() }
