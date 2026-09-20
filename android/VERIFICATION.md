# Android verification — 2026-09-20

## Final timestamp and installed-app follow-up

- The final timestamp changes passed offline `checkKotlinFormat`, app and consumer
  unit tests, both debug APK builds, and Android Lint. Results: **18 app tests passed
  / 1 skipped**, **22 consumer tests passed / 1 skipped**; the skips require the
  separate real-backend host harness. Lint remains **0 errors / 11 warnings**.
- The timestamp regression covers English and Chinese formatting, the local date
  boundary, a daylight-saving transition, and preservation of the original
  nanosecond timestamp. Selection formats only the visible label, retaining raw
  chart timestamps and canonical values.
- Reinstalled final APKs passed **English 3/3 and Simplified Chinese 3/3** focused
  instrumentation tests, with no failures or skips. The selected-point timestamp
  assertion ran in both languages. Eight current synthetic screenshots were
  exported; the updated metric screens show localized local time instead of ISO
  timestamps, and both metric layouts were visually inspected.
- The full `ConnectedUiTests` scenario also passed separately in **English 1/1
  and Simplified Chinese 1/1**, each against a fresh disposable PostgreSQL/API.
  This verifies restored login, pagination, cycling/running metric navigation,
  settings and equipment writes, training history, logout and vault clearing.
  The first Chinese attempt reached its 120-second test limit while waiting for
  UI idleness. An isolated rerun with a 240-second limit passed in 58 seconds;
  the English run passed in 88 seconds. No app change was made between them,
  and the precise cause of the earlier timeout is not established.
- These installed runs used bounded direct ADB instrumentation, including
  `-e class com.aifitness.LocalizedJourneyTests,com.aifitness.LocalizationTests`
  for the focused journeys and `-e class com.aifitness.ConnectedUiTests` for the
  full scenario, with the disposable server and explicit locale arguments.
  They establish current app behavior; they do not establish that the historical
  Gradle/UTP result-collection stall below has been fixed.
- Physical devices, older Android versions, large-font settings and pseudolocales
  remain outside this verification. No generated files, screenshots or temporary
  test databases belong in Git.

## Earlier localization follow-up

- Offline `formatKotlin :app:testDebugUnitTest :consumer:test :app:assembleDebug
  :app:lintDebug` passed. App unit tests: **17 passed, 1 skipped**; shared JVM
  consumer: **21 passed, 1 skipped**. Both skips are the standalone real-backend
  integration case; these invocations do not provision its server. The new
  `responseBudgetRejectsOversizeBeforeJsonDecoding` regression ran in both modules.
- Final debug app and instrumentation APK builds and Android Lint passed after
  the localization test updates. Lint reported **0 errors, 11 warnings**; the
  additional notice concerns `localeConfig` being ignored below API 33, where
  the app uses the system language. Dependencies and locks were unchanged.
- `checkLocalization` passed for **249 resources**: 247 strings and 2 plurals.
  Checks cover matching English/Simplified Chinese keys, positional argument
  types, plural branches, referenced resources, and deliberately missing or
  incompatible translations. It runs with `preBuild` and `checkKotlinFormat`.
- Installed APK acceptance passed on the existing Android 15 ARM64 emulator:
  **English 3/3** and **Simplified Chinese 3/3**, with no failures or skips.
  `LocalizedJourneyTests` exercised login, workout details, the actual metric
  screen and settings against a disposable PostgreSQL/API with synthetic records.
  `LocalizationTests` verified packaged language configuration, English regional
  and unsupported-language fallback, Chinese script/region aliases, ordered
  language preferences, plurals, live configuration changes, verbatim user title
  `settings` and mixed-language notes, and unchanged canonical workout JSON.
  Eight synthetic screenshots covered login/workout/metric/settings in both
  languages; representative screens were visually inspected. Direct ADB
  instrumentation was used for these bounded runs; the temporary server and
  database were removed afterward.
- The older full `ConnectedUiTests` scenario **did not pass this follow-up**:
  it hit a Compose-Espresso idling timeout, and Gradle/UTP then stalled while
  collecting results. Its earlier successful result below is historical, not
  evidence that its full restore/pagination/settings-write/history/logout path
  passed at that checkpoint. The later direct-run results above supersede this
  app-flow coverage gap. The shorter bilingual acceptance runs do not replace
  that broader regression coverage. Physical devices, older Android versions,
  large-font settings and pseudolocales were not exercised in this follow-up.

## Initial client verification (before localization)

The results below record the initial client baseline. Current localization
acceptance and the historical runner limitation are stated above.

- Pinned official ktfmt CLI applied Kotlin language style to all **20 maintained
  Kotlin source/build files** (including Compose and instrumentation); generated
  and build directories were excluded. The non-mutating parsing/format check
  passed, separately from native SDK compilation:

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
- After the operator explicitly accepted the SDK license, installed the official
  Mac ARM command-line tools 22.0 under ignored `.tooling/sdk`. The download's
  SHA-256 matched Google's published value:
  `835b62a26162b229b441d1f6d4680383815a270809eb33522c0d480fa5002c4e`.
  Native checks used SDK 35, Build Tools 35.0.0, emulator 37.1.11 and the default
  API 35 ARM64 system image revision 2. No global SDK installation was added.
- `:app:assembleDebug :app:testDebugUnitTest :app:lintDebug` passed, first with
  `--write-locks`, then without it to verify the maintained native dependency lock.
  App unit results: **12 passed**, with the separate HTTP integration case skipped
  because this standalone invocation does not provision a backend. That boundary
  is covered by the successful host and device integration runs described here.
  Android Lint: **0 errors, 10 warnings** (seven newer-dependency notices, one
  launcher-icon notice, two optional KTX-edit suggestions). Explicit synchronous
  preference commits retain their failure checks; dependencies were not upgraded.
- `-PcontractOnly checkKotlinFormat` also passed with both SDK environment variables
  unset after the shared Kotlin-plugin configuration change.
- Installed and launched the debug APK on a disposable ARM64 Android 15 emulator.
  `scripts/android_integration_test --device` then passed against a fresh real
  PostgreSQL/API: **one instrumented scenario, zero failures, errors or skips**.
  It covers login, Android Keystore ciphertext storage and session restoration
  after Activity recreation, 20+3 workout pagination, cycling power navigation,
  running step-length/oscillation/contact charts on time and distance axes,
  running analysis, body persistence read back from the server, equipment creation,
  explicit training-history inputs, return navigation, logout and vault clearing.
  Only synthetic fixtures were used; the harness removed its database and server.

Local ignored evidence: `build/format.log`, `build/format-check.log`,
`build/connected.log`,
`consumer/build/test-results/test/TEST-*.xml` and
`consumer/build/reports/tests/test/index.html`; native evidence is in
`build/native-check.log`, `build/native-locked-check.log`,
`build/format-contract-only.log`, `build/device-connected.log`,
`app/build/test-results/testDebugUnitTest/`,
`app/build/reports/lint-results-debug.html` and
`app/build/outputs/androidTest-results/connected/debug/`.
Reproduction commands are in README.

## Remaining boundaries

The native run covers one Android 15 ARM64 emulator, not a physical-device or
multi-version matrix. Release signing/distribution and actual OS backup/restore
were not exercised. Lint checks the explicit backup/transfer exclusion policy;
the device test checks local Keystore persistence, not a backup transport.

The route is a native interactive trace with raw-point selection; street/satellite
basemaps are not implemented.

## Maintained changed paths

Only these new Android files and Android scripts belong to this change. Generated
contracts, dependency caches, build outputs and test databases are excluded.

- `android/.gitignore`
- `android/README.md`
- `android/VERIFICATION.md`
- `android/app/build.gradle.kts`
- `android/app/gradle.lockfile`
- `android/app/src/androidTest/java/com/aifitness/ConnectedUiTests.kt`
- `android/app/src/androidTest/java/com/aifitness/LocalizationTests.kt`
- `android/app/src/androidTest/java/com/aifitness/LocalizedJourneyTests.kt`
- `android/app/src/debug/res/xml/network_security_config.xml`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/java/com/aifitness/Charts.kt`
- `android/app/src/main/java/com/aifitness/CredentialVault.kt`
- `android/app/src/main/java/com/aifitness/FitnessApi.kt`
- `android/app/src/main/java/com/aifitness/FitnessViewModel.kt`
- `android/app/src/main/java/com/aifitness/HistoryScreen.kt`
- `android/app/src/main/java/com/aifitness/MainActivity.kt`
- `android/app/src/main/java/com/aifitness/Localization.kt`
- `android/app/src/main/java/com/aifitness/SessionVault.kt`
- `android/app/src/main/java/com/aifitness/SettingsScreens.kt`
- `android/app/src/main/java/com/aifitness/TrainingCalendar.kt`
- `android/app/src/main/java/com/aifitness/WorkoutDetailScreen.kt`
- `android/app/src/main/java/com/aifitness/WorkoutPresentation.kt`
- `android/app/src/main/res/values/styles.xml`
- `android/app/src/main/res/values/strings.xml`
- `android/app/src/main/res/values-b+zh+Hans/strings.xml`
- `android/app/src/main/res/xml/locales_config.xml`
- `android/app/src/main/res/xml/data_extraction_rules.xml`
- `android/app/src/main/res/xml/network_security_config.xml`
- `android/app/src/test/java/com/aifitness/ConnectedApiTests.kt`
- `android/app/src/test/java/com/aifitness/ContractTests.kt`
- `android/build.gradle.kts`
- `android/check_localization.py`
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
