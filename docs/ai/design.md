# Shared Design Rules

**Read when:** introducing an abstraction, changing model/state ownership, or reviewing a cross-component design.

**One owner for domain decisions.** The Haskell backend owns canonical validation, normalization, authoritative calculations, and persistence rules. Web/native clients own presentation, interaction, permission handling, platform integration, and the local state needed for those responsibilities. Client-side form checks improve feedback but never replace backend validation.

**Logical boundaries, not mandatory layers.** A typical operation crosses transport handling, application orchestration, domain rules, and infrastructure. These do not require four folders, four interfaces, or four almost-identical records. Start with direct functions and split where responsibilities actually diverge.

**Model meaning, not incidental representation.** Use named types for concepts that are easy to confuse, such as workout IDs, distances, and durations. Distinguish missing, unavailable, invalid, and zero where behavior differs. Prefer variants for mutually exclusive states; do not mechanically replace every Boolean or every optional field with a new type.

**Preserve semantics when simplifying.** Refactoring must preserve effects, evaluation order where observable, error precedence, cancellation, and input/output meaning. Shorter syntax is not evidence of equivalence. Add a behavioral test when the equivalence is not obvious.

**Keep state ownership explicit.** A stateful value needs an owner and a lifetime. Do not add an independent copy of the same remote data in a query cache, global store, component, and database without a defined reason and synchronization policy. Editable drafts are legitimate separate state when their commit/reset rules are explicit.

**Name the domain.** Prefer `normalizeWorkout`, `loadWorkout`, and `saveBike` over vague `processData` or `Manager` abstractions. Use English identifiers and repository documentation, matching existing conventions. Comments explain constraints and reasons. Public boundaries document units, failure behavior, and ownership when types do not make them clear. [repo-agent]

**Require evidence for extra machinery.** Before introducing a new abstraction, cache, service, or dependency, compare it with the direct implementation. Test the variant without that machinery when practical. Keep the machinery only when it improves required behavior, clarity, or measured performance. This is not permission to remove an approved framework during an unrelated task.

[repo-agent]: references.md#repo-agent
