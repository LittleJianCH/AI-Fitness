# Stack and Adoption Status

**Read when:** making technology choices, checking implementation status, or resolving architecture conflicts.

## What is actually present

The running Haskell backend uses IHP configuration/logging, Servant `GET /api/v1/hello`, and Warp. Pure canonical workout/import operations and a Servant-derived API contract pipeline also exist. TypeScript and Swift contract consumers are generated and checked independently of the running server. PostgreSQL, authentication and product handlers are not implemented. The web/ directory contains a minimal SvelteKit frontend with a static homepage, strict TypeScript, ESLint and Prettier. Local FIT parsing supports the initial cycling/running subset through the Garmin SDK; it is not connected to an upload handler. Native mobile apps, the MCP server and GitHub Actions are not initialized. See the [contract guide](../api-contract.md) for the current boundary. [repo-readme] [repo-architecture] [repo-tree]

The root flake supplies the current development shell. Haskell packages/tools come from IHP's package set; general tools come from the configured Nixpkgs 26.05 input. IHP's input references its `v1.6` branch; `flake.lock`, rather than the moving branch name, pins the fetched dependency graph. The Haskell package declares `Haskell2010`. Do not silently upgrade the compiler, language edition, framework, or dependency graph to match examples from newer documentation. [repo-flake] [repo-cabal]

## Stack and adoption status

| Area | Selected direction | Status and boundary |
| --- | --- | --- |
| Backend | Haskell, IHP infrastructure, Servant, WAI/Warp | Minimal implementation exists. IHP MVC views/controllers are not the product API architecture. |
| Database | PostgreSQL using the selected IHP version's Hasql-based infrastructure | Planned; no database integration exists in the inspected skeleton. |
| Application effects | `effectful` | Previously discussed/selected for application effects, but absent from current dependencies. Introduce only for a current orchestration need; pure domain code does not require it. |
| API contract | Servant-derived OpenAPI 3.1 | Draft implemented, with a tested 3.0-to-3.1 conversion and TypeScript/Swift contract consumers; feature handlers remain future work. |
| Web | Svelte 5, SvelteKit, strict TypeScript | Initialized in `web/` with a static homepage; no API integration yet. SvelteKit is not a second domain backend. |
| Web API/state | Orval, TanStack Svelte Query, boundary validation with Zod | Orval generates a fetch client for contract checks. Zod is installed in web/ but not used by the static homepage yet. Query integration and application boundary validation remain future work. |
| Web effects | Effect (`effect`) | Approved, not default and not installed. Introduce locally when concrete effect orchestration justifies it; start with direct TypeScript. Svelte retains UI state ownership. |
| Web presentation | Tailwind CSS, shadcn-svelte/Bits UI, ECharts | Carried-forward UI choices; introduce only components needed by the active feature. |
| iOS | Swift, SwiftUI, HealthKit; URLSession, Keychain; Swift OpenAPI Generator | Planned native client. SwiftData is the planned local persistence option, not a requirement to duplicate the full server database. |
| Android | Kotlin, Jetpack Compose | Latest native-client direction. Coroutines/Flow and ViewModel are recommended implementation defaults, not existing code. |
| Android supporting choices | Gradle Kotlin DSL; Health Connect/Room when required | Proposed or conditional. Network library, Kotlin API generator, persistence scope, and SDK levels remain to be settled. No Kotlin Multiplatform baseline. |
| MCP server | Separate Go adapter calling the Haskell API over HTTP/JSON | Planned. Prefer the official Go MCP SDK after compatibility verification. No direct database access or duplicate domain engine. |
| FIT | Haskell FFI → thin C ABI → Garmin C++ FIT SDK | Initial cycling/running subset implemented in Import.Fit with a pinned Garmin SDK. No upload/storage integration or parser CLI/subprocess; see the backend architecture for coverage and limits. |
| Storage/deployment | PostgreSQL plus local filesystem, local/single-machine deployment | Planned baseline. Do not introduce S3/MinIO, orchestration, queues, or distributed services without a concrete requirement. |
| Environment | One root Nix flake and lockfile; language-native manifests/locks | Root development environment exists; the full multi-language build/check pipeline does not. |
| Automation | GitHub collaboration; GitHub Actions as CI direction | No workflow is present in the inspected tree. Add checks incrementally. |
| Experimental extensions | Lisp/Scheme tagging or query rules; configurable AI services | Exploratory/feature-specific, not a mandate to add an interpreter, effect system, or plugin platform now. |

Versions belong in executable manifests and lockfiles, not in a second independently maintained version table. Official language documentation informs implementation but does not authorize changing selected frameworks.

## Known stale decisions to correct before implementation

Multi-source workout merging has been removed. The architecture and [API contract](../api-contract.md) now describe username/password login with a shared opaque-session lifecycle and separate browser/native transports. Historical snapshots with merging or the previous token table are superseded; MCP credentials remain a separate future decision. [repo-architecture]

OpenAPI 3.1 is the current repository target, despite older material discussing 3.0.x. Prove the actual Servant → specification → client chain. Do not declare a 3.0 document to be 3.1 by merely changing its version string. Any temporary 3.0.x bridge needs an explicit, tested, documented decision. [repo-architecture] [openapi]

## Status discipline

Originally reviewed on 2026-09-11, with model and API-contract status updated on 2026-09-12. Recheck the current repository before claiming a feature is missing or selecting/upgrading dependencies. Carried-forward web/mobile choices remain selected/proposed/planned unless executable manifests and checks establish their adoption.

In these guides, MUST denotes a project boundary or correctness requirement, SHOULD a default allowing a justified exception, and MAY an optional technique. Suggested tools remain proposals until adopted in executable configuration.

[openapi]: references.md#openapi
[repo-architecture]: references.md#repo-architecture
[repo-cabal]: references.md#repo-cabal
[repo-flake]: references.md#repo-flake
[repo-readme]: references.md#repo-readme
[repo-tree]: references.md#repo-tree
