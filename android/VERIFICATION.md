# Android verification — 2026-09-20

## Completed checks

- Pinned official ktfmt CLI applied Kotlin language style to all **20 maintained
  Kotlin source/build files** (including Compose and instrumentation); generated
  and build directories were excluded. The non-mutating parsing/format check
  passed, separately from the unavailable native SDK compilation:

  ```sh
  android/gradlew -p android -PcontractOnly formatKotlin
  android/gradlew -p android -PcontractOnly checkKotlinFormat --console=plain
  ```

  `checkKotlinFormat`: **BUILD SUCCESSFUL**, 20 inputs, no changes required.
  The formatter is an isolated build-only dependency pinned/locked in the root
  Android build files, with no runtime framework added.

- Pinned Gradle distribution and wrapper JAR verified against official SHA-256 checksums.
- Kotlin consumer compilation passed on JDK17, including generated contracts,
  the application's HTTP transport, lifecycle ViewModel, calendar and chart projections.
- After formatting, final `scripts/android_integration_test --host` passed: **16 tests, zero failures,
  errors or skips**. A private disposable PostgreSQL cluster, account and 23 synthetic
  workouts exercised the actual Haskell backend; no production records were used.
- Actual HTTP coverage: login and `/me` session validation, 20+3 pagination, cycling and
  running detail/analysis/power curves, grade/temperature, distributions/relationships,
  power and HR zones, splits, body/settings persistence and revision conflicts,
  equipment rename/retirement, unknown/rest training days, sessions and logout revocation.
- Focused regressions: required/optional/null parsing, exact large decimal revision
  strings, unknown enums, subnanosecond server times, endpoint restrictions, redirect
  refusal, request cancellation, DST, hidden chart gaps, independent distance sampling,
  partial analysis failures and retry, history return navigation, actionable analysis errors,
  exact/hidden distance resets, running-metric precision and raw-chart navigation
  without a derived analysis response.
- Two clean OpenAPI-to-Kotlin generations were byte-identical. Python, shell and
  Android XML syntax and maintained-file whitespace checks passed.

Local ignored evidence: `build/format.log`, `build/format-check.log`,
`build/connected.log`,
`consumer/build/test-results/test/TEST-*.xml` and
`consumer/build/reports/tests/test/index.html`. Reproduction commands are in README.

## Not verified

The Android SDK and an emulator were unavailable, with SDK terms awaiting explicit
operator acceptance. `:app:assembleDebug`, `:app:testDebugUnitTest`, Android Lint,
APK installation, Compose UI, Keystore on a device and `connectedDebugAndroidTest`
were **not run**. The SDK-free consumer does not prove those native boundaries.
No native dependency lock has been resolved yet; the consumer lock is maintained in this change.
The instrumentation harness is implemented for a disposable authorized runtime.

The route is a native interactive trace with raw-point selection; street/satellite
basemaps are not implemented. No SDK license was accepted automatically, no global
tooling was installed by this client task.

## Maintained changed paths

Only these new Android files and Android scripts belong to this change. Generated
contracts, dependency caches, build outputs and test databases are excluded.

- `android/.gitignore`
- `android/README.md`
- `android/VERIFICATION.md`
- `android/app/build.gradle.kts`
- `android/app/src/androidTest/java/com/aifitness/ConnectedUiTests.kt`
- `android/app/src/debug/res/xml/network_security_config.xml`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/java/com/aifitness/Charts.kt`
- `android/app/src/main/java/com/aifitness/CredentialVault.kt`
- `android/app/src/main/java/com/aifitness/FitnessApi.kt`
- `android/app/src/main/java/com/aifitness/FitnessViewModel.kt`
- `android/app/src/main/java/com/aifitness/HistoryScreen.kt`
- `android/app/src/main/java/com/aifitness/MainActivity.kt`
- `android/app/src/main/java/com/aifitness/SessionVault.kt`
- `android/app/src/main/java/com/aifitness/SettingsScreens.kt`
- `android/app/src/main/java/com/aifitness/TrainingCalendar.kt`
- `android/app/src/main/java/com/aifitness/WorkoutDetailScreen.kt`
- `android/app/src/main/java/com/aifitness/WorkoutPresentation.kt`
- `android/app/src/main/res/values/styles.xml`
- `android/app/src/main/res/xml/network_security_config.xml`
- `android/app/src/test/java/com/aifitness/ConnectedApiTests.kt`
- `android/app/src/test/java/com/aifitness/ContractTests.kt`
- `android/build.gradle.kts`
- `android/consumer/build.gradle.kts`
- `android/consumer/gradle.lockfile`
- `android/consumer/src/test/kotlin/com/aifitness/TransportTests.kt`
- `android/consumer/src/test/kotlin/com/aifitness/ViewModelTests.kt`
- `android/gradle.lockfile`
- `android/gradle.properties`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/gradlew`
- `android/gradlew.bat`
- `android/settings.gradle.kts`
- `scripts/android_generate`
- `scripts/android_integration_test`
- `scripts/android_test_account.py`
