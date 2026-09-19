# Stack and Adoption Status

**Read when:** making technology choices, checking implementation status, or resolving architecture conflicts.

## What is actually present

The Haskell backend uses IHP configuration, Servant, Hasql pooling and Warp.
Mounted features include authentication, owned workouts, FIT/HealthKit imports,
export receipts, personal settings, workout analysis and HRSS training history.
Pure domain checks, contract consumers and isolated PostgreSQL/HTTP checks cover
separate boundaries. Group and file-export handlers remain unmounted. See the
[contract guide](../api-contract.md) for the exact route boundary.

Web uses SvelteKit with generated Orval/Zod contracts and connected backend
workflows; its synthetic demo is an explicit separate mode. iOS uses SwiftUI,
generated API transport, Keychain sessions and explicit HealthKit import/export.
Android now has a Kotlin/Compose client, generated DTO/codecs, platform HTTP
transport and Keystore sessions. All clients consume Haskell analysis and settings.
Android's shared JVM consumer and native device checks are separate; a passing
host check does not establish native build/UI behavior. The MCP server and GitHub
Actions remain uninitialized. [repo-readme] [repo-architecture] [repo-tree]

The root flake supplies the current development shell. Haskell packages/tools come from IHP's package set; general tools come from the configured Nixpkgs 26.05 input. IHP's input references its `v1.6` branch; `flake.lock`, rather than the moving branch name, pins the fetched dependency graph. The Haskell package declares `Haskell2010`. Do not silently upgrade the compiler, language edition, framework, or dependency graph to match examples from newer documentation. [repo-flake] [repo-cabal]

## Stack and adoption status

| Area | Selected direction | Status and boundary |
| --- | --- | --- |
| Backend | Haskell, IHP infrastructure, Servant, WAI/Warp | Minimal implementation exists. IHP MVC views/controllers are not the product API architecture. |
| Database | PostgreSQL using the selected IHP version's Hasql-based infrastructure | User/session/workout/settings storage, submission identity and IHP SQL migrations implemented; HTTP handlers use a bounded Hasql pool. |
| Application effects | `effectful` | Previously discussed/selected for application effects, but absent from current dependencies. Introduce only for a current orchestration need; pure domain code does not require it. |
| API contract | Servant-derived OpenAPI 3.1 | Draft implemented with a tested 3.0-to-3.1 conversion and TypeScript/Swift/Kotlin consumers. The API contract guide identifies mounted handlers and contract-only routes. |
| Web | Svelte 5, SvelteKit, strict TypeScript | Connected training-review application in `web/`, plus an explicit synthetic fixture demo. SvelteKit is not a second domain backend. |
| Web API/state | Orval, TanStack Svelte Query, boundary validation with Zod | Orval generates read clients and Zod response validators. TanStack Query owns remote request/cache state; Zod validates HTTP responses before rendering. |
| Web effects | Effect (`effect`) | Approved, not default and not installed. Introduce locally when concrete effect orchestration justifies it; start with direct TypeScript. Svelte retains UI state ownership. |
| Web presentation | Tailwind CSS, shadcn-svelte/Bits UI, ECharts | ECharts is used for metric plots, and Tabler Icons supplies outline symbols. Tailwind and shadcn/Bits UI remain planned; current layout uses local CSS and native controls. Visual rules live in [Web UI Design](../web-design.md). |
| iOS | Swift, SwiftUI, HealthKit; URLSession, Keychain; Swift OpenAPI Generator | SwiftUI login, backend workout list/detail with charts/routes, generated Swift API transport and Keychain sessions implemented in `ios/`. HealthKit selection/preview, explicit import and confirmed platform export are implemented. Export uses protected local recovery records and backend receipts; synthetic simulator tests exercise HealthKit writes and relaunch retries. Physical-device acceptance remains separate from synthetic tests. SwiftData is conditional on actual local persistence needs; it does not duplicate the server database. |
| Android | Kotlin, Jetpack Compose, coroutines/Flow and ViewModel | Client sources in `android/` provide login, workout analysis, settings and training history. Shared JVM HTTP/contract checks and instrumented UI checks have distinct verification boundaries. |
| Android supporting choices | Gradle Kotlin DSL/Wrapper, platform HttpURLConnection/JSON, Android Keystore | Executable manifests pin Kotlin/Compose/AGP/SDK inputs; the root Android Nix shell supplies JDK17. DTO/codecs derive from the shared OpenAPI. No Health Connect, Room, networking framework or Kotlin Multiplatform baseline is introduced. |
| MCP server | Separate Go adapter calling the Haskell API over HTTP/JSON | Planned. Prefer the official Go MCP SDK after compatibility verification. No direct database access or duplicate domain engine. |
| FIT | Haskell FFI → thin C ABI → Garmin C++ FIT SDK | Initial cycling/running subset and authenticated upload/archive integration exist. No parser CLI/subprocess; see the backend architecture for coverage and limits. |
| Storage/deployment | PostgreSQL plus local filesystem, local/single-machine deployment | PostgreSQL and private FIT archive persistence are implemented; deployment remains separate. Do not introduce S3/MinIO, orchestration, queues, or distributed services without a concrete requirement. |
| Environment | One root Nix flake and lockfile; language-native manifests/locks | Root development environment exists; the full multi-language build/check pipeline does not. |
| Automation | GitHub collaboration; GitHub Actions as CI direction | No workflow is present in the inspected tree. Add checks incrementally. |
| Experimental extensions | Lisp/Scheme tagging or query rules; configurable AI services | Exploratory/feature-specific, not a mandate to add an interpreter, effect system, or plugin platform now. |

Versions belong in executable manifests and lockfiles, not in a second independently maintained version table. Official language documentation informs implementation but does not authorize changing selected frameworks.

## Known stale decisions to correct before implementation

Multi-source workout merging has been removed. The architecture and [API contract](../api-contract.md) now describe username/password login with a shared opaque-session lifecycle and separate browser/native transports. Historical snapshots with merging or the previous token table are superseded; MCP credentials remain a separate future decision. [repo-architecture]

OpenAPI 3.1 is the current repository target, despite older material discussing 3.0.x. Prove the actual Servant → specification → client chain. Do not declare a 3.0 document to be 3.1 by merely changing its version string. Any temporary 3.0.x bridge needs an explicit, tested, documented decision. [repo-architecture] [openapi]

## Status discipline

Originally reviewed on 2026-09-11, with client/analysis adoption updated on
2026-09-20. Recheck the current repository and actual verification results before
claiming a feature or runtime is complete. Executable manifests and checks
establish adoption; planned choices alone do not.

In these guides, MUST denotes a project boundary or correctness requirement, SHOULD a default allowing a justified exception, and MAY an optional technique. Suggested tools remain proposals until adopted in executable configuration.

[openapi]: references.md#openapi
[repo-architecture]: references.md#repo-architecture
[repo-cabal]: references.md#repo-cabal
[repo-flake]: references.md#repo-flake
[repo-readme]: references.md#repo-readme
[repo-tree]: references.md#repo-tree
