# AI Fitness Web

A Svelte 5 / SvelteKit training-review demo with strict TypeScript. It follows
[Web UI Design](../docs/web-design.md): desktop is primary and the same workflow
is developed and checked at mobile widths.

## Start the demo

From the repository root, with the pinned Nix environment available:

```sh
./scripts/web_generate
./scripts/web_dev
pnpm install --frozen-lockfile
pnpm demo
```

Open http://127.0.0.1:5173/workouts. The first command builds the Haskell contract
and its synthetic response fixtures, installs the locked contract tooling, and
generates the TypeScript client and Zod validators. Repeat it after API changes.
Generated files under `src/lib/api/generated/` are ignored by Git.

`pnpm demo` explicitly enables a local, read-only fixture transport. All four
workouts and their routes are synthetic. The banner exposes normal, slow, empty,
server failure, invalid payload and unauthenticated scenarios. No credentials,
FIT files or personal data are read, written or transmitted. Route diagrams use
synthetic WGS84 points without a basemap or external provider requests.

The backend implements authentication and manual Workout persistence, including
owned list and detail reads. The web demo still uses fixture transport and focuses
on list → overview → metric/route detail. Authentication, upload, persistence,
editing, training-load calculations and AI analysis are not simulated as success.

`pnpm dev` uses the ordinary environment without fixture endpoints. It needs
an authenticated browser session and same-origin routing to the backend before
it can show real workouts. Browser login integration and deployment routing remain
to be connected; the backend enforces the API contract's ownership rules.

## What to try

- Filter cycling/running, load the next page, open a workout and use browser back.
- Open heart rate, select samples by chart hover/click or keyboard-accessible
  slider/buttons, and open the sample table. Escape releases a pinned chart cursor.
- Compare full data with the indoor summary-only and running-without-HR records.
- Use the scenario selector to inspect loading, empty, recoverable failure,
  invalid response and session failure states.
- Resize between the desktop chart/map columns and the mobile single column.

## Checks and builds

Inside the Web development shell, after generation:

```sh
pnpm check
pnpm lint
pnpm test
pnpm build:demo
pnpm exec playwright install chromium
pnpm test:e2e
```

`pnpm format` applies Prettier. `pnpm test` checks generated validators against
actual synthetic Servant responses, presentation semantics and the demo HTTP
transport. Browser tests start their own demo server on loopback port 5180.
They cover desktop and mobile Chromium, including state/error paths and layout
widths. Screenshots/traces live under ignored `test-results/`.

`pnpm preview:demo` previews a `pnpm build:demo` build with the same explicit
fixture transport. `pnpm build` builds ordinary mode and `pnpm preview` previews
it without fixtures. Adapter-auto remains a scaffold choice; deployment is a
separate task, and a successful build does not establish production readiness.

The Web generator also has a repeatability check: run `npm run check:web` from
`contracts/` in the root Nix shell. It compares the client and Zod validators
against two independently generated output directories.

## Data flow and ownership

```text
Servant types → OpenAPI → Orval client + Zod response schemas
                                  ↓
TanStack Query → generated fetch → same-origin HTTP
                     ↑              ↓
                 validated response ← demo fixture transport (demo mode only)
                     ↓
                 Svelte views → ECharts / route diagram
```

`contracts/web.config.ts` selects the two GET operations used here and reuses the
existing fetch generator. Its input adapter normalizes JSON media-type parameters
for Orval's Zod renderer. A pinned renderer adaptation uses Zod `guid()` to match
Haskell's UUID codec, which accepts canonical hex groups without restricting the
version/variant bits. Actual Servant response tests guard both compatibility fixes.

Each root layout owns its QueryClient. Query owns remote data and request
cancellation; Svelte owns filters, local selection and responsive presentation.
Errors expose safe user-facing messages rather than payloads. Revisions stay as
strings. DTOs are generated; presentation projections retain canonical field and
unit meaning. Recorded statistics come from the response, not chart points.

ECharts draws elapsed-time samples without smoothing or bridging display gaps
over two minutes. This is an explicit rendering rule, not a pause detector or a
statistical calculation. A sample selector and table provide accessible values.
The route view is a schematic preview rather than a geographic basemap.

Zod is the default boundary validator. Effect remains approved for complex future
workflows but is not installed. Tailwind and shadcn/Bits UI remain available
choices for later features; this demo uses local CSS and semantic native controls.
Tabler Icons supplies the shared outline icon family through per-icon Svelte imports.
