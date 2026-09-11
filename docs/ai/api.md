# API Contracts and Generated Code

**Read when:** changing endpoints, wire DTOs, serialization, OpenAPI, or generated clients.

The intended flow is `Servant API/DTO definitions → OpenAPI → TypeScript, Swift, Kotlin, and Go clients`. Kotlin is an added contract consumer, not a second API source of truth. Generator selection remains part of each client's implementation task. The public wire schema is shared; framework models, persistence objects, and every internal Haskell type are not. [repo-architecture] [openapi] [orval]

Keep names, IDs, units, timestamps, required/optional/null semantics, tagged unions, pagination, and error responses explicit. Use string IDs or another representation that all clients can round-trip exactly. Do not use clever generic encodings that compile in one language but become `any` or unusable models in another.

First prove a small contract containing an identifier, timestamp, optional value, tagged alternative, success response, and error response. Generate and compile the relevant clients. Validate encoding behavior against the real server; schema syntax validity alone is insufficient. A generated client is not a runtime proof that an endpoint obeys the schema.

Do not commit reproducible derived clients, generated database types, build products, or manually edited generated outputs unless explicitly authorized. Commit the generator configuration, source definitions, reproducible generation command, necessary dependency locks, and maintained migrations. A lockfile is an intentional build input, not a disposable build artifact. Approved bootstrap files, such as the Gradle Wrapper, need the same deliberate distinction.

Because generated outputs are ignored, an empty `git diff` after generation does not prove determinism. Generate into clean temporary directories, compare normalized outputs where necessary, and compile consumers in CI. Do not introduce a duplicate hand-maintained OpenAPI specification as a convenient shortcut.

[openapi]: references.md#openapi
[orval]: references.md#orval
[repo-architecture]: references.md#repo-architecture
