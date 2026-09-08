# AGENTS.md

## Project

AI Fitness is a personal fitness and training data system.

This project is developed collaboratively by a human developer and AI coding agents.

The goal is not only to build the product, but also to keep the human developer able to understand, modify, and maintain the entire system.

---

## Development Principle

The human developer leads architecture and product decisions.

AI agents act as pair programmers, implementation assistants, reviewers, and research assistants.

Do not optimize for maximum code generation speed.

Optimize for:

1. correctness,
2. simplicity,
3. understandability,
4. small reviewable changes,
5. learning value for the human developer.

Prefer the simplest implementation that satisfies the current requirement.

Do not introduce abstractions for hypothetical future requirements.

---

## Scope Discipline

Implement only the requested task.

Do not expand scope without explicit approval.

Do not introduce unrelated:

- frameworks,
- abstractions,
- infrastructure,
- services,
- dependencies,
- refactors,
- architectural layers.

If a task appears to require a larger architectural change, explain why before implementing it.

Prefer incremental changes over broad rewrites.

---

## Human Understanding

The human developer is learning frontend and backend development through this project.

Do not hide important behavior behind generated code or unnecessary abstractions.

When introducing an important new concept, briefly explain:

- what problem it solves,
- where it sits in the system,
- how data flows through it,
- why this implementation is chosen.

Core project behavior should remain understandable from the source code.

Generated code must not be committed unless explicitly requested.

---

## Change Size

Keep changes small and reviewable.

A change should normally solve one coherent problem.

Avoid large mixed-purpose pull requests.

If implementation becomes significantly larger than expected, stop expanding the change and identify how it can be split.

Do not combine unrelated refactoring with feature development.

---

## Architecture Decisions

Do not make major architecture decisions implicitly.

Architecture-affecting decisions include, but are not limited to:

- changing major frameworks,
- introducing a new service,
- changing database ownership or boundaries,
- changing API conventions,
- introducing asynchronous infrastructure,
- introducing a new abstraction layer,
- changing authentication architecture,
- changing canonical domain models.

For these decisions, present the tradeoff before implementation.

Keep important architecture decisions in the existing architecture document rather than only in code or chat history. Update it when the design changes; create a separate ADR only when explicitly requested.

---

## Implementation Style

Prefer:

- explicit code,
- strong types,
- small modules,
- clear data flow,
- pure functions where practical,
- direct implementations before abstractions.

Avoid:

- speculative generalization,
- premature optimization,
- unnecessary indirection,
- framework-heavy solutions for simple problems,
- compatibility layers that are not currently required.

Comments should explain why, not restate what the code already says.

---

## Testing

Tests should verify externally meaningful behavior.

Prefer testing:

- domain invariants,
- API behavior,
- parsing behavior,
- database behavior where relevant,
- important failure cases.

Avoid tests that only mirror implementation details.

Every bug fix should include a regression test when practical.

---

## Dependencies

Do not add a dependency when the standard library or existing dependencies solve the problem cleanly.

Before adding a significant dependency, explain:

- what problem it solves,
- why existing tools are insufficient,
- its maintenance implications.

---

## Repository Hygiene

Do not commit:

- generated build artifacts,
- generated API clients,
- temporary files,
- editor state,
- local secrets,
- credentials,
- unrelated formatting changes.

Keep commits focused.

A commit should represent one understandable logical change.

---

## Working Process

For non-trivial tasks, use this sequence:

1. Understand the requirement.
2. Identify relevant existing code.
3. State the smallest intended change.
4. Implement it.
5. Run relevant tests and checks.
6. Review the diff for unnecessary changes.
7. Summarize what changed and anything the human developer should understand.

Do not continue implementing additional ideas merely because they become apparent during the task.

---

## Current Development Strategy

AI Fitness is being rebuilt incrementally from a clean foundation.

The initial priority is learning and establishing the basic frontend/backend data flow.

Advanced functionality should not be introduced until needed.

In particular, do not prematurely introduce:

- FIT ingestion,
- HealthKit integration,
- MCP integration,
- recommendation algorithms,
- background job systems,
- distributed services,
- complex authentication,
- deployment infrastructure.

These will be added incrementally when the project reaches them.

---

## Source of Truth

Prefer executable sources of truth over duplicated documentation.

Examples:

- domain rules → types and tests,
- database structure → migrations/schema,
- API contract → API definition/OpenAPI,
- build environment → Nix configuration,
- behavior → implementation and tests.

Documentation should explain decisions and intent, not duplicate large amounts of code structure.

If documentation and implementation disagree, point out the inconsistency instead of silently choosing one.

---

## When Unsure

Do not guess silently.

If uncertainty could materially affect architecture, data integrity, or public interfaces, explain the uncertainty before making the decision.

For small implementation details, choose the simplest reasonable solution and document the assumption in the final summary.

## Documentation

Write repository documentation in English. Keep architecture and usage documents
in sync with implementation changes. The architecture is an evolving design,
not an immutable plan. Do not create separate ADRs unless explicitly requested.
