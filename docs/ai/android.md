# Kotlin and Android

**Read when:** editing Kotlin/Compose or Android platform integration.

Use Kotlin and Jetpack Compose idiomatically; do not recreate a Haskell effect system or introduce Clojure/Kotlin Multiplatform/Arrow to make the stack look uniform. Prefer `val`, small data classes, explicit null handling, and sealed hierarchies when alternatives really are exclusive. A `val` reference or read-only `List` is not automatically deeply immutable. Keep scope functions and extension functions short and recognizable; avoid chains of `let`/`also`/`apply` that hide the receiver or control flow. [kotlin-style]

Use a screen-level ViewModel when state must outlive recomposition or coordinate data. Expose read-only state, generally `StateFlow`; retain mutation ownership internally. Composables accept state and emit user actions. Collect flows lifecycle-aware, and place actual side effects in the appropriate lifecycle/effect mechanism rather than the composable body. Do not manufacture a generic base ViewModel or a use-case class for every button. [android-architecture]

Use structured coroutines with `viewModelScope` or a clearly owned scope. Make blocking operations main-safe through the appropriate dispatcher; `suspend` alone does not relocate them. Inject dispatchers where useful for tests. Do not use `GlobalScope` for normal feature work or swallow `CancellationException` through broad catches/`runCatching`. Use immutable snapshots or controlled ownership when updating UI collections. [android-coroutines]

Keep networking and platform adapters outside views. Select one compatible HTTP/client-generation path when Android implementation begins; do not install both Retrofit and Ktor without a concrete need. Use Room only when persistence/offline synchronization requires it. Use Health Connect only for explicitly requested integrations, accounting for availability, permissions, and platform-specific read limitations rather than assuming HealthKit parity. [health-connect]

Use Gradle Kotlin DSL and the checked-in Gradle Wrapper. Pin compatible Kotlin, Compose, Android Gradle Plugin, JDK, and SDK settings in executable configuration. Suggested checks are Kotlin formatting with one adopted tool such as ktlint, Android Lint, unit/coroutine tests, and focused Compose UI tests; add detekt only for useful nonduplicated analysis.

[android-architecture]: references.md#android-architecture
[android-coroutines]: references.md#android-coroutines
[health-connect]: references.md#health-connect
[kotlin-style]: references.md#kotlin-style
