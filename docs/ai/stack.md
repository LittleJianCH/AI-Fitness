# Stack and Adoption Status

**Read when:** making technology choices, checking implementation status, or resolving architecture conflicts.

## What is actually present

The inspected default branch contains a minimal Haskell backend. IHP supplies configuration/logging, Servant exposes `GET /api/v1/hello`, and Warp runs the application. PostgreSQL initialization, domain features, authentication, OpenAPI generation, and clients are not implemented in this skeleton. The frontend is explicitly not initialized. No iOS, Android, MCP, FIT integration, or GitHub Actions workflow appears in the inspected tree. [repo-readme] [repo-architecture] [repo-tree]

The root flake supplies the current development shell. Haskell packages/tools come from IHP's package set; general tools come from the configured Nixpkgs 26.05 input. IHP's input references its `v1.6` branch; `flake.lock`, rather than the moving branch name, pins the fetched dependency graph. The Haskell package declares `Haskell2010`. Do not silently upgrade the compiler, language edition, framework, or dependency graph to match examples from newer documentation. [repo-flake] [repo-cabal]

## Stack and adoption status

| Area | Selected direction | Status and boundary |
| --- | --- | --- |
| Backend | Haskell, IHP infrastructure, Servant, WAI/Warp | Minimal implementation exists. IHP MVC views/controllers are not the product API architecture. |
| Database | PostgreSQL using the selected IHP version's Hasql-based infrastructure | Planned; no database integration exists in the inspected skeleton. |
| Application effects | `effectful` | Previously discussed/selected for application effects, but absent from current dependencies. Introduce only for a current orchestration need; pure domain code does not require it. |
| API contract | Servant-derived OpenAPI; target OpenAPI 3.1 | Planned. The generator/toolchain compatibility is not yet demonstrated. |
| Web | Svelte 5, SvelteKit, strict TypeScript | Selected direction; not initialized. SvelteKit is not a second domain backend. |
| Web API/state | Orval, TanStack Svelte Query, boundary validation with Zod | Carried-forward plan; not installed. Verify compatible generator/adapter versions when needed. |
| Web presentation | Tailwind CSS, shadcn-svelte/Bits UI, ECharts | Carried-forward UI choices; introduce only components needed by the active feature. |
| iOS | Swift, SwiftUI, HealthKit; URLSession, Keychain; Swift OpenAPI Generator | Planned native client. SwiftData is the planned local persistence option, not a requirement to duplicate the full server database. |
| Android | Kotlin, Jetpack Compose | Latest native-client direction. Coroutines/Flow and ViewModel are recommended implementation defaults, not existing code. |
| Android supporting choices | Gradle Kotlin DSL; Health Connect/Room when required | Proposed or conditional. Network library, Kotlin API generator, persistence scope, and SDK levels remain to be settled. No Kotlin Multiplatform baseline. |
| MCP server | Separate Go adapter calling the Haskell API over HTTP/JSON | Planned. Prefer the official Go MCP SDK after compatibility verification. No direct database access or duplicate domain engine. |
| FIT | Haskell FFI → thin C ABI → Garmin C++ FIT SDK | Selected in-process boundary; not implemented. No parser CLI/subprocess. Buffer representation/ABI details are not fixed by this guide. |
| Storage/deployment | PostgreSQL plus local filesystem, local/single-machine deployment | Planned baseline. Do not introduce S3/MinIO, orchestration, queues, or distributed services without a concrete requirement. |
| Environment | One root Nix flake and lockfile; language-native manifests/locks | Root development environment exists; the full multi-language build/check pipeline does not. |
| Automation | GitHub collaboration; GitHub Actions as CI direction | No workflow is present in the inspected tree. Add checks incrementally. |
| Experimental extensions | Lisp/Scheme tagging or query rules; configurable AI services | Exploratory/feature-specific, not a mandate to add an interpreter, effect system, or plugin platform now. |

Versions belong in executable manifests and lockfiles, not in a second independently maintained version table. Official language documentation informs implementation but does not authorize changing selected frameworks.

## Known stale decisions to correct before implementation

The repository architecture document still mentions workout merging and the old web-session/iOS-token/MCP-token authentication table. These conflict with the owner's later decisions. **Do not implement those sections as current requirements.** Multi-source workout merging has been removed. Web username/password registration and login are required; the full authentication/session/token architecture is to be redesigned rather than inherited. [repo-architecture]

OpenAPI 3.1 is the current repository target, despite older material discussing 3.0.x. Prove the actual Servant → specification → client chain. Do not declare a 3.0 document to be 3.1 by merely changing its version string. Any temporary 3.0.x bridge needs an explicit, tested, documented decision. [repo-architecture] [openapi]

## Status discipline

This is the 2026-09-11 review snapshot. Its inspected commit was `1e11564e30f7b1eddf6ef00887664b252eb51bd6`; immediately before integrating these guides, `main` was rechecked and still pointed to that commit. Recheck the current repository before claiming that a feature is still missing or selecting/upgrading a dependency. The carried-forward web/mobile choices were not independently re-researched during modularization, so keep them at their stated selected/proposed/planned status rather than turning optional choices into new requirements.

In these guides, MUST denotes a project boundary or correctness requirement, SHOULD a default allowing a justified exception, and MAY an optional technique. Suggested tools remain proposals until adopted in executable configuration.

[openapi]: references.md#openapi
[repo-architecture]: references.md#repo-architecture
[repo-cabal]: references.md#repo-cabal
[repo-flake]: references.md#repo-flake
[repo-readme]: references.md#repo-readme
[repo-tree]: references.md#repo-tree
