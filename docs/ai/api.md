# API Contracts and Generated Code

**Read when:** changing endpoints, wire DTOs, serialization, OpenAPI, or generated clients.

The intended flow is `Servant API/DTO definitions → OpenAPI → TypeScript, Swift, Kotlin, and Go clients`. Kotlin is an added contract consumer, not a second API source of truth. The public wire schema is shared; framework models, persistence objects, and every internal Haskell type are not. [repo-architecture] [openapi] [orval]

Reuse canonical workout measurement types across the model and API when their meaning is genuinely identical. Keep serialization and OpenAPI instances in boundary modules; define separate request, response, or projection types when their semantics differ from the canonical model.

Keep names, IDs, units, timestamps, required/optional/null semantics, tagged unions, pagination, and error responses explicit. Use representations every supported client can round-trip exactly. Do not use clever generic encodings that compile in one language but become `any`, lossy numbers, or unusable models in another.

## Verification depends on the stage

The repository already has a tested contract pipeline. For a **contract-only change**, reuse the existing schema/codec regressions and generated-consumer checks documented in `docs/api-contract.md`. Add a new minimal compatibility regression only when the changed shape exposes a new generator/encoding edge case. Do not repeatedly recreate the original proof-of-concept contract.

For an **implemented HTTP feature**, add verification for real request/response behavior and the boundaries it actually uses, such as authentication, authorization, persistence, concurrency, or binary handling. Generated clients and synthetic contract fixtures do not prove that a mounted handler enforces domain or persistence rules.

Do not implement unrelated product handlers merely to satisfy a generic instruction to test against a live server. Report clearly when a change verifies only the contract layer versus the running product behavior.

Do not commit reproducible derived clients, generated specifications, generated database types, build products, or manually edited generated outputs unless explicitly authorized. Commit generator configuration, source definitions/codecs, reproducible generation commands, necessary dependency locks, maintained migrations, and compatibility tests. A lockfile is an intentional build input, not a disposable build artifact.

Because generated outputs are ignored, an empty `git diff` after generation does not prove determinism. Use the repository's existing clean-output comparison/compile checks where configured. Do not introduce a duplicate hand-maintained OpenAPI specification as a shortcut.

[openapi]: references.md#openapi
[orval]: references.md#orval
[repo-architecture]: references.md#repo-architecture
