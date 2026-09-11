# Testing and Verification Strategy

**Read when:** adding/changing tests, fixing a bug, or designing verification for a change.

Test domain invariants, parser behavior, API contracts, actual persistence constraints, and meaningful failure cases. Favor small pure tests and focused integration tests over extensive mock scaffolding. Bug fixes should normally add regression coverage. Property tests are useful only for properties that actually hold: normalization idempotence requires a defined normalization policy; FIT round-trips compare the documented representable canonical projection, not necessarily the original bytes.

Choose verification by the changed behavior, not by the number of guide files. Use the relevant language/integration guide for suggested tools and the repository's executable configuration for actual commands. A contract/storage/security change needs coverage for that boundary even if only one implementation language is edited. Do not load every platform guide for an unaffected internal refactor.

For a documentation-only change, check local links, routing destinations, reference anchors, and whether rules were lost or contradicted. These checks are not a substitute for compilation or application tests.
