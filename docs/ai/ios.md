# Swift and iOS

**Read when:** editing Swift/SwiftUI, HealthKit, or iOS synchronization.

Follow Swift API Design Guidelines: call-site clarity, meaningful argument labels, and standard naming are more valuable than minimal character count. Prefer value types and `let` for data. Use enums with associated values for exclusive states; avoid routine force unwraps, `try!`, and `try?` that silently discard actionable failures. Introduce protocols at actual substitution boundaries, not beside every concrete class. [swift-api]

Keep SwiftUI views focused on rendering and interaction. Put synchronization and permission orchestration outside view bodies. Keep UI-owned mutable state under explicit main-actor isolation. Use Observation when supported by the chosen deployment target; do not assume its availability or perform an unrelated framework migration.

Use structured `async`/`await` work with a clear owner and cancellation behavior. `async` does not by itself mean CPU work runs off the UI executor. Do not scatter `Task.detached`, `DispatchQueue.main.async`, or unchecked `Sendable` annotations to silence concurrency diagnostics. Respect isolation across suspension points and transfer appropriate value data rather than actor-confined persistence objects. Verify the pinned Swift language mode and Xcode concurrency settings before selecting APIs.

Keep URLSession/generated API transport separate from HealthKit integration and local persistence. SwiftData records are local storage models, not the public API contract. Maintain only the local cache/sync state justified by the feature. Store secrets through the platform's secure credential facilities, not ordinary preference records or logs; this does not predetermine the new server authentication design.

HealthKit permissions are per capability/data type. Do not treat an empty result as proof of zero activity or universal authorization. Handle unavailable, denied/restricted, and missing-data cases according to what the platform actually exposes. If incremental synchronization is implemented, commit imported records before advancing its checkpoint, and prevent export/import feedback loops using explicit source identifiers. Do not turn that bookkeeping into the removed multi-source merge feature. [healthkit]

Suggested checks: the adopted `swift-format` configuration, Swift compiler/concurrency diagnostics, Swift Testing or existing XCTest tests, and focused XCUITest coverage. Xcode/macOS/device-dependent checks must be reported separately from portable checks.

[healthkit]: references.md#healthkit
[swift-api]: references.md#swift-api
