# AI Fitness — Agent Instructions

The human owns product and architecture decisions and is learning the system with AI assistance. Optimize for correctness, simplicity, understandability, and small reviewable changes—not code volume.

## Always apply

- Implement only the requested task. Start with direct code; do not add speculative layers, dependencies, services, or unrelated refactors. Explain material architectural changes before implementing them. Do not scaffold planned features merely because a guide mentions them.
- Prefer pure calculations, explicit effects, meaningful types, and clear state ownership, using each language's idioms. Preserve behavior, errors, cancellation, and observable ordering during refactors. The Haskell backend owns authoritative domain rules; clients/adapters do not duplicate them.
- Code, manifests, and tests establish what exists; the owner's latest explicit decisions establish intended behavior. Surface conflicts. Do not restore removed multi-source workout merging or the superseded authentication design. Retry deduplication is not semantic merging.
- Protect credentials, health records, and routes. Do not expose them in logs, fixtures, or external AI calls without the appropriate explicit policy. Enforce authorization server-side.
- Follow configured formatters and checks. Prefer existing dependencies; justify additions. Do not commit generated clients/build outputs, secrets, unrelated formatting, or accidental lockfile changes. Necessary dependency locks and maintained migrations are not disposable generated artifacts.
- Test meaningful behavior and failure paths; normally add regression coverage for fixes. Report changed behavior, important data flow, exact checks run/results, skipped checks, and remaining assumptions. Never claim an unrun check passed.
- Keep commits focused. Do not push, merge, or rewrite shared history without authorization. Explain unfamiliar concepts briefly. Use English identifiers and repository documentation; update affected existing architecture/usage documents. Do not create ADRs unless requested.

## Read only the rules the task needs

Select rows by **behavior and affected boundaries**, not only by file extension. Paths below are repository-relative. Read selected files once; do not read the entire directory or follow every reference. Sources and the full stack are lookup material, not startup prerequisites. If scope expands, load the newly relevant rules before editing that boundary. For delegated work, supply the task, relevant decisions, and selected paths—not the full guide or conversation.

| Task touches | Read |
| --- | --- |
| Haskell implementation | `docs/ai/haskell.md` |
| Web TypeScript, Svelte, UI state | `docs/ai/web.md` |
| Swift, SwiftUI, HealthKit | `docs/ai/ios.md` |
| Kotlin, Compose, Android integration | `docs/ai/android.md` |
| Go MCP tools or transport | `docs/ai/mcp.md` |
| Garmin SDK, C++, native ABI, FIT decoding | `docs/ai/fit-ffi.md` |
| New abstractions, model design, state ownership | `docs/ai/design.md` |
| Canonical units/time, import/export policy, Bike or source semantics | `docs/ai/domain-data.md` |
| Database, migrations, filesystem, persistence | `docs/ai/storage.md` |
| HTTP/wire behavior, DTOs, OpenAPI, client generation | `docs/ai/api.md` |
| Nix, dependencies, toolchain, build/CI setup | `docs/ai/nix.md` |
| Authentication, authorization, sensitive-data exposure, external providers | `docs/ai/security.md` |
| Tests, bug fixes, verification design | `docs/ai/testing.md` |
| Stack selection, adoption status, architecture conflicts | `docs/ai/stack.md` |
| Source evidence or external compatibility needs checking | `docs/ai/references.md` — only relevant entries |

Load consumer-language guides only when consumer implementation is affected. An API/schema change still requires identifying affected consumers and checks; a pure internal helper does not require every client guide. Keep each detailed rule in its owning file; do not paste all topic rules back into this entry point.
