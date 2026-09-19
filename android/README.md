# Android client

Native Kotlin / Jetpack Compose client for the owner-scoped AI Fitness API.
The backend owns all physiological calculations, statistics, distributions,
relationships, zones, splits and training history. Android owns screen state,
formatting, calendar boundaries and chart interaction.

## Pinned baseline

The executable versions live in [plugin and repository settings](settings.gradle.kts),
[app build inputs](app/build.gradle.kts), [build tooling](build.gradle.kts),
and [wrapper properties](gradle/wrapper/gradle-wrapper.properties). JDK selection
belongs to the root `flake.nix` Android shell. Read those files for exact pins.

Compatibility references verified on 2026-09-19:
[AGP 8.9 compatibility](https://developer.android.com/build/releases/agp-8-9-0-release-notes),
[Kotlin Gradle compatibility](https://kotlinlang.org/docs/gradle-configure-project.html),
[Compose compiler setup](https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler).
These are fixed compatible inputs, not claims to be the newest releases.
The official wrapper is from Gradle's `v8.11.1` Git tag and its JAR is checked against the official
[wrapper checksum](https://services.gradle.org/distributions/gradle-8.11.1-wrapper.jar.sha256).
It verifies the official [distribution checksum](https://services.gradle.org/distributions/gradle-8.11.1-bin.zip.sha256).

Supply an Android SDK whose terms have been explicitly accepted by its operator.
Do not accept licenses automatically or install Android tooling globally.
The current host is macOS arm64; use an arm64 emulator image if an emulator is
provisioned. SDK/emulator packages are not installed by these scripts.

## Contract generation and local checks

Prepare the backend executable, contract fixtures and OpenAPI artifact with
`nix develop -c make -C backend all contract contract-test`, then run
`nix develop -c bash -c 'cd contracts && npm ci --ignore-scripts && npm run generate'`. Android adds no schema
copy and makes no changes to the canonical contract.

From the repository root:

```sh
scripts/android_generate
nix develop .#android -c bash
export GRADLE_USER_HOME="$PWD/android/.gradle-home"
# These checks need JDK17 but no Android SDK:
android/gradlew -p android -PcontractOnly checkKotlinFormat :consumer:test
# Apply the same formatter when editing Kotlin:
android/gradlew -p android -PcontractOnly formatKotlin
# Supply ANDROID_HOME to an existing, authorized SDK:
android/gradlew -p android :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

`formatKotlin` / `checkKotlinFormat` invoke the single pinned [ktfmt CLI](https://github.com/Kotlin/ktfmt)
using Kotlin language style (four-space indentation). The version is in the root
Android build script; the isolated formatter configuration has its own dependency
lock and never enters the app runtime. Both tasks cover every maintained app,
instrumentation, JVM test and consumer `.kt` file plus Gradle Kotlin DSL files,
excluding generated/build directories. The check fails for parse errors or
format differences. It verifies Kotlin parsing/formatting, not Android symbols,
Compose type checking, Android Lint or device behavior. The [official CLI options](https://github.com/Kotlin/ktfmt/blob/v0.64/core/src/main/java/com/facebook/ktfmt/cli/ParsedArgs.kt)
define the Kotlin style and non-mutating failure check used by these tasks.

The small `consumer` verification module compiles the **same source files** as
the app: HTTP transport, generated DTOs, the lifecycle ViewModel, presentation
projections and calendar adapter. A minimal credential-vault interface keeps the
Keystore implementation on Android while testing the same state transitions. It is not an alternate client implementation. It enables contract and
real-backend checks without an Android runtime; it does not prove Compose,
Keystore, manifest behavior or device execution.

`scripts/android_generate` reads `contracts/build/openapi.json`, recursively
selects the consumed schemas, and produces ignored Kotlin DTOs and JSON codecs.
It preserves revision strings exactly, rejects absent required properties,
explicit null, numeric strings and unknown enum/union alternatives, and tolerates
unknown object properties. UTC strings preserve the server's original precision;
display uses native nanoseconds. Arrays retain independent sample timestamps.
Generated Kotlin is a build output, never edited or committed. Native parsing
uses the platform `org.json` implementation; host checks pin its JVM counterpart.

Tests consume backend-generated synthetic `*-response.json` fixtures. The Android
unit task expects them in `../backend/build` relative to the Android project.
Dependency locks are maintained build inputs; refresh intentionally with
`--write-locks` when changing declared versions.

## Real backend verification

The harness requires the root backend Nix shell, a `JAVA_HOME` pointing at the
pinned JDK17 and the backend/fixtures built by the prerequisite commands above. It creates a private
PostgreSQL socket-only cluster, applies the maintained backend migrations, starts
a backend on an ephemeral loopback port, provisions one synthetic account and
23 cycling/running workouts, and cleans up on exit. It discards any inherited
production database selection and uses a private FIT archive directory.

```sh
# Inside the backend Nix shell, with the pinned JAVA_HOME supplied:
scripts/android_integration_test --host
# With an authorized SDK and an already-running disposable emulator/device:
scripts/android_integration_test --device
```

Host integration exercises actual native login, `/me`, both workout pages,
detail/analysis/power-curve decoding, settings persistence and stale revisions,
body history, equipment retirement, unknown/rest history and session revocation.
The device harness uses `adb reverse` for its ephemeral backend and runs Compose
instrumentation against actual HTTP. It does not grant permissions, create an
emulator, or download SDK packages. Use a disposable emulator because the test
signs the client into its synthetic account. No production health data is used.

## Behavior and boundaries

- Login restores an encrypted native session and validates it through `/me`.
  AES-GCM ciphertext lives in private preferences; its key lives in Android
  Keystore. Backup is disabled. Passwords are never persisted or saveable state.
  A 401 clears the session. Logout clears credentials after server revocation;
  failed logout keeps the credential for retry. Explicit local removal is
  labelled as not revoking the server session.
- HTTPS is required in release. Debug permits cleartext only for `localhost`,
  `127.0.0.1`, `::1`, and Android emulator host `10.0.2.2`. Endpoint validation
  rejects user info, query credentials, fragments and unrelated path prefixes.
  Redirects are rejected; response caching is disabled. HTTP work and decoding
  run on the IO dispatcher, cancellation disconnects the connection, and raw
  credentials/server diagnostics are not logged or displayed.
- Workout lists use opaque cursors and deduplicate IDs. Detail checks workout
  identity and revision against both analysis endpoints. Recorded data and route
  publish first; analysis and power curve have independent errors/retries, and
  stale revisions explicitly request a detail refresh. A settings write clears
  prior analysis/history. Lifecycle-owned jobs prevent late cancelled requests
  from repopulating a different screen or account.
- Detail order is route/recorded overview, metrics, power/running dynamics,
  heart-rate load, distance splits/source laps, source context and method notes.
  Metric pages show raw samples, backend statistics, distributions and aligned
  relationships. Grade and temperature are supported when present.
- Charts bound drawn points while preserving full-stream gaps first; point
  selection uses the raw stream. Distance axes use independently sampled distance
  only within valid intervals, never extrapolating. Chart coordinate mapping,
  unit conversion and pace formatting are presentation, not a second analysis
  implementation. Source/recorded statistics are labelled separately.
- The route is an interactive native Canvas trace with start/end markers,
  pan/zoom and a full-screen view. There are no external map tiles or location
  uploads. A satellite/street basemap is not implemented.
- Settings categories are software, body parameters, equipment and account.
  Bodies append immutable effective-dated profiles; cycling and running HR/FTP
  remain separate. Equipment supports creation, renaming, mass and retirement.
  Server revisions/validation are authoritative. Account controls include session
  listing/revocation, password changes and logout.
- Training history requires explicit prior load or explicit zero-prior choice,
  and explicit recording completeness. Local dates use `java.time` zone rules,
  including DST. Opening history from a workout returns to that workout. Unknown days stay unknown; Android does not calculate HRSS,
  CTL, ATL, TSB, normalized power, splits or other domain results.

No Health Connect, offline database, automatic sync, networking framework,
external map provider or release deployment is introduced.
