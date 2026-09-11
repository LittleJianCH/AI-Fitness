# TypeScript and SvelteKit

**Read when:** editing web code, rendering, interactive state, or browser integration.

Use strict TypeScript. Treat unvalidated external values as `unknown`, not `any`; avoid double assertions, non-null assertions, or `@ts-ignore` as substitutes for modeling. Add stricter optional/index access settings after testing the selected dependencies, not by silently breaking the build. Generated TypeScript types alone do not perform runtime validation. [typescript]

Consume the generated API contract rather than retyping backend responses. Keep API DTOs distinct from UI state when their semantics differ. Use tagged unions for exclusive states and ordinary records for independent states; refreshing existing data, for example, need not discard it into a data-less `loading` variant.

For new Svelte 5 code, use `$props`, `$state`, and `$derived` deliberately. Derive values instead of using `$effect` to copy one piece of state into another. Effects are for synchronizing with external systems, such as chart instances, and need cleanup. Framework-native local mutation of `$state` is not a violation of the project's functional principles. [svelte-effects]

SvelteKit routing/loading and TanStack Query must have a defined ownership boundary. Once Query owns an interactive remote resource, do not independently fetch and cache the same resource through another mechanism without coordinating hydration/invalidation. Create user-specific SSR state and query clients per request/component context, not module-global singletons. Keep server secrets and private modules out of browser bundles. [svelte-state] [orval]

SvelteKit MAY perform rendering, routing, and thin transport adaptation. It MUST NOT acquire independent database ownership or implement a second copy of domain calculations. A server route is not inherently forbidden, but business-heavy `+server.ts` endpoints require an architectural discussion.

Use semantic HTML, labeled controls, keyboard access, and explicit loading/empty/error states. Preserve the product's mobile-first, predominantly single-column layout: show the main chart and use drill-down views for detail rather than shrinking text to fit every metric. Social features, friends, leaderboards, badges, and a route library are outside product scope.

Suggested checks: Prettier with the Svelte plugin, ESLint, `svelte-check`, Vitest for pure/component behavior, and a small Playwright suite for critical journeys. Install/configure only what the active frontend needs. Do not claim these scripts exist before checking `package.json`. [svelte-testing]

[orval]: references.md#orval
[svelte-effects]: references.md#svelte-effects
[svelte-state]: references.md#svelte-state
[svelte-testing]: references.md#svelte-testing
[typescript]: references.md#typescript
