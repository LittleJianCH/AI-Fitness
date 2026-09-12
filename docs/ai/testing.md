# Testing and Verification Strategy

**Read when:** adding/changing tests, fixing a bug, or designing verification for a change.

Test domain invariants, parser behavior, API contracts, actual persistence constraints, and meaningful failure cases. Favor small pure tests and focused integration tests over extensive mock scaffolding. Bug fixes should normally add regression coverage. Property tests are useful only for properties that actually hold: normalization idempotence requires a defined normalization policy; FIT round-trips compare the documented representable canonical projection, not necessarily the original bytes.

Choose verification by the changed behavior, not by the number of guide files. Start with the smallest relevant configured checks. Broaden to integration, generated-consumer, native, platform, or larger suites when the changed boundary, dependency graph, a failure, or explicit acceptance criteria justify it. Do not run unrelated exhaustive suites merely because they exist.

Within an authorized task, safe local tests use disposable/synthetic fixtures unless a guide explicitly says otherwise. Run them, fix failures introduced by the requested change, and rerun affected checks without asking for approval at each iteration. Existing unrelated failures should be reported rather than silently repaired through scope expansion.

Use the relevant language/integration guide for tool-specific constraints and executable configuration for actual commands. A contract/storage/security change needs coverage for that boundary even if only one implementation language is edited. Do not load every platform guide for an unaffected internal refactor.

For a documentation-only change, check local links, routing destinations, reference anchors, and whether rules were lost or contradicted. These checks are not a substitute for compilation or application tests.
