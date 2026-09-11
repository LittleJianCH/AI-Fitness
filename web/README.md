# AI Fitness Web

Minimal Svelte 5 / SvelteKit app with strict TypeScript, scaffolded with the
[official Svelte CLI](https://svelte.dev/docs/cli/sv-create) (`sv@0.17.0`).

See [Web UI Design](../docs/web-design.md) for the desktop-priority visual and
interaction baseline and joint desktop/mobile acceptance. The current homepage
is a development placeholder.

## Development

From the repository root:

```sh
./scripts/web_dev
pnpm install --frozen-lockfile
pnpm dev
```

Open http://localhost:5173. The root Nix flake pins Node and pnpm through its
existing lockfile; `pnpm-lock.yaml` pins the web dependencies. The dedicated `web`
shell avoids loading the Haskell toolchain. Run `pnpm install` after intentionally
changing dependencies and keep the updated lockfile with the manifest.

## Checks

Inside the web development shell:

```sh
pnpm check
pnpm lint
pnpm build
```

`pnpm format` applies Prettier. `pnpm preview` serves the production build locally.
The scaffold uses adapter-auto; select an adapter for the deployment target when
hosting is decided. A successful build is not a deployment configuration.

## Structure and scope

- `src/app.html`: HTML document shell.
- `src/routes/+layout.svelte`: shared layout, rendering each page through `children`.
- `src/routes/+page.svelte`: the `/` page, including its title and styles.
- `vite.config.ts`: SvelteKit integration and development/build configuration.

The homepage is a static development placeholder. There are no API requests,
authentication, workout data, generated clients or domain calculations yet.
The Haskell backend remains the owner of domain rules. Query, UI and chart
libraries should be introduced with the features that need them.

Type and lint checks plus a production build cover this initial scaffold; no
unit or browser test suite is configured yet.

## Validation and effects

Zod is the default runtime validation library and is installed. The static
homepage does not use it yet. Use it at untrusted boundaries such as persisted
browser data, URL parameters, imported JSON, external responses and forms.
Prefer generated runtime schemas when the API contract pipeline supports them
reliably. Do not hand-maintain a duplicate schema for every generated API DTO;
add handwritten validation only at boundaries that need it and cannot use a
generated schema. Static TypeScript types do not validate runtime data.
The Haskell backend remains authoritative for domain rules and authorization.

Effect is approved but is not a default dependency and is not installed. Start
with direct TypeScript and async/await. Introduce Effect locally when a concrete
workflow benefits from composing typed errors, retries, timeouts, cancellation,
concurrency or resource lifetimes; compare it with the direct implementation.
Do not wrap ordinary Svelte state, simple transformations or straightforward
Query calls in Effect for stylistic consistency. Svelte owns local UI state;
TanStack Query is the planned owner of interactive remote state.

Do not introduce Effect Schema unless Effect becomes a meaningful part of the
web application architecture. If that happens, reassess schema ownership rather
than maintaining equivalent Zod and Effect schemas in parallel.
Orval and TanStack Query remain planned, not installed.
