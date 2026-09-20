# AI Fitness — Agent Instructions

The human owns product and architecture decisions and is learning the system with AI assistance. Optimize for correctness, simplicity, understandability, and small reviewable changes—not code volume.

## Always apply

- Implement the requested task without speculative layers, services, dependencies, or unrelated refactors. Explain material product or architecture changes before making them. Do not scaffold planned features merely because a guide mentions them.
- Prefer pure calculations, explicit effects, meaningful types, and clear state ownership, using each language's idioms. Preserve behavior, errors, cancellation, and observable ordering during refactors. The Haskell backend owns authoritative domain rules; clients and adapters do not duplicate them.
- Code, manifests, tests, and current repository documentation establish what exists. The owner's latest explicit decisions establish intended behavior. Surface conflicts instead of silently choosing an older document.
- Protect credentials, health records, and routes. Do not expose them in logs, fixtures, or external AI calls without the appropriate explicit policy. Enforce authorization server-side.
- Follow configured formatters and checks. Prefer existing dependencies; justify additions. Do not commit generated clients/build outputs, secrets, unrelated formatting, or accidental lockfile changes. Necessary dependency locks and maintained migrations are not disposable generated artifacts.
- Keep commits focused. Do not push, merge, rewrite shared history, use production data, or perform other externally consequential actions without authorization.
- Use English identifiers and repository documentation. Update affected architecture or usage docs when behavior changes. Do not create ADRs unless requested.

## Complete authorized work without needless checkpoints

Within the requested scope, make the necessary local edits, run the relevant safe local checks, fix failures caused by the change, and rerun affected checks without asking for approval at every step. A task is complete when the requested behavior and its relevant verification are complete, or when a concrete blocker is reported—not merely when a first implementation exists.

Stop for a decision when continuing would require an unapproved product behavior, public contract, data-handling policy, major dependency, architecture change, or external action. If the user explicitly asks for a review checkpoint before continuing, honor that checkpoint.

Choose verification by changed behavior. Prefer the smallest relevant checks first; broaden only when the boundary, dependencies, failures, or requested acceptance criteria justify it. Never claim an unrun check passed.

## Read only what the task needs

Select guidance by **behavior and affected boundaries**, not by file extension alone. Do not load the whole documentation set before ordinary work. Avoid rereading unchanged material already available in context; reread the relevant section when the file changed, the task scope expands, or the needed detail is no longer reliable in context.

| Task touches | Read |
| --- | --- |
| Haskell implementation | `docs/ai/haskell.md` |
| Web TypeScript, Svelte, UI state | `docs/ai/web.md` |
| Web visual design, responsive layout, navigation, charts | `docs/web-design.md` |
| User-visible copy, localization, locale selection, date/measurement formatting | `docs/ai/i18n.md` and the relevant client guide |
| Swift, SwiftUI, HealthKit | `docs/ai/ios.md` |
| Kotlin, Compose, Android integration | `docs/ai/android.md` |
| Go MCP tools or transport | `docs/ai/mcp.md` |
| Garmin SDK, C++, native ABI, FIT decoding | `docs/ai/fit-ffi.md` |
| New abstractions, model design, state ownership | `docs/ai/design.md` |
| Canonical units/time, import/export policy, Bike or source semantics | `docs/ai/domain-data.md` |
| Database, migrations, filesystem, persistence | `docs/ai/storage.md` |
| HTTP/wire behavior, DTOs, OpenAPI, client generation | `docs/ai/api.md` and the relevant part of `docs/api-contract.md` |
| Nix, dependencies, toolchain, build/CI setup | `docs/ai/nix.md` plus executable manifests/configuration |
| Authentication, authorization, sensitive-data exposure, external providers | `docs/ai/security.md` and the relevant authentication contract |
| Tests, bug fixes, verification design | `docs/ai/testing.md` |
| Stack selection, adoption status, architecture conflicts | `docs/ai/stack.md`; consult the relevant part of `docs/backend-architecture.md` when a service/domain boundary is involved |
| Source evidence or external compatibility needs checking | `docs/ai/references.md` — only relevant entries |

For a typo, comment, or purely mechanical formatting change, do not load a language or architecture guide unless the change actually touches its semantics. Load consumer-language guides only when consumer implementation is affected. For delegated work, supply the task, relevant decisions, and selected paths—not the full guide or conversation.

Keep detailed rules in their owning files rather than copying them back into this entry point.
