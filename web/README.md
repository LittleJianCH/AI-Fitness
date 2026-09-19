# AI Fitness Web

A Svelte 5 / SvelteKit training-review application with strict TypeScript. It follows
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
Login, workout write forms and account settings are available only in connected mode.

`pnpm dev` uses the ordinary environment without fixture endpoints. It needs
an authenticated browser session and same-origin routing to the backend before
it can show real workouts. The browser restores its session before mounting private pages. The backend
enforces the API contract's ownership rules.

## Local HTTPS and API routing

Inside `./scripts/web_dev`, run `../scripts/web_certificate` once, then `pnpm dev`.
The certificate is self-signed, expires after 90 days and stays in ignored
`web/.certs/`. Trust that leaf certificate locally in your browser/OS before using
real credentials, or supply a trusted certificate with `AI_FITNESS_TLS_CERT` and
`AI_FITNESS_TLS_KEY` (absolute file paths). The script does not install a system CA.
Remove both generated files explicitly to renew them. Never commit private keys.

Use `https://localhost:5173` consistently. Vite terminates local TLS and proxies
`/api/` to `http://127.0.0.1:8000`, preserving Origin, Cookie and Set-Cookie.
`AI_FITNESS_API_TARGET` overrides the backend target. Port conflicts fail instead
of silently changing the origin. The backend's `APP_ORIGIN` must match the browser
origin exactly (its default is already `https://localhost:5173`). Start PostgreSQL,
apply migrations and run the backend as described in the root README. Registration
is closed by default; enable `REGISTRATION_OPEN=true` when creating an account.

This proxy is for development. Ordinary build/preview does not need local keys
and does not install a production proxy. Demo mode retains its independent HTTP
fixture server. Production hosting must supply the same-origin HTTPS entry point.

## Browser login and real records

Ordinary mode supports policy-controlled registration, separate login, session
restoration and logout. A direct private-page visit returns to that destination
after login. Expired/revoked sessions return to login. The session cookie remains
HttpOnly; CSRF tokens and form drafts stay in memory. The root layout owns the
browser session and its QueryClient. Private query keys include the current user;
logout, expiry and account changes abort requests, remove private queries and
unmount private views. Cross-tab session changes carry only an invalidation message.
Focus/visibility checks detect an expired or externally changed browser session.

The existing list, overview and metric/route pages read the authenticated user's
real records. Empty sensor streams retain their missing-data presentation. Demo
labels are only shown in explicit demo mode. Network failures preserve a retry
path and server error codes map to safe local messages.

From the repository root, after installing/generating Web dependencies, run:

```sh
./scripts/web_integration_test
```

This builds the real backend and creates a disposable PostgreSQL cluster with
synthetic accounts and records, ignoring any developer `DATABASE_URL`. Desktop
and mobile Chromium use the HTTPS proxy on port 5181 and the backend on 8181.
Each test gets a fresh backend process (isolating its rate-limit window); the
cluster persists for explicit restart checks and is removed on exit. Tests
accept their temporary self-signed certificate; this does not verify system trust
for a developer's certificate. Run `pnpm exec playwright install chromium` in the
Web shell once if Chromium is missing. Artifacts remain in ignored `test-results/`.

## Manual workouts

Use **手动录入** from the real training list. Choose cycling/running, a local start
instant and elapsed minutes/seconds (including pauses); distance in kilometres,
title, notes and tags are optional. The browser converts the entered units to
canonical seconds/metres and UTC instants. Impossible dates/local times are rejected.
The backend validates and persists the canonical observation. Unentered distances
stay absent; zero stays zero. Sensor streams and unavailable statistics stay empty;
no calculated summaries or synthetic measurements are added to manual records.

Drafts remain in memory and leaving a dirty form asks for confirmation. Saving
opens the returned record and invalidates the owner's list. If a success response
is lost, the form retains the same submission ID and body for explicit retry,
preventing duplicate creation. An uncertain attempt locks its fields until the
result is resolved. A definitive input rejection permits correction only when no
earlier response for that attempt left publication uncertain.
A late response updates the cache without taking over a page the user navigated to.
Reloading discards the in-memory draft/attempt; check the list before recording the
same activity again after an uncertain save.

## Editing and deletion

Connected workout details link to a metadata editor. The editor captures the current
revision as a string. Editing changes title, notes and tags; the user-data request
also preserves the existing statistics inclusion policy. Background reads do not replace an open draft.
On a revision conflict, the draft remains visible and writes stay blocked until the
user explicitly loads the latest version. Leaving an unsaved draft requires confirmation.
Deletion requires confirmation and the captured revision. The backend currently
supports deletion of manual records only; other records display its rejection.
Drafts stay in memory and are cleared on account changes. Demo routes expose no editor.

## Filters and account settings

The workout URL stores optional `sport`, local calendar `from` and `through` dates,
and an exact `tag`. The date range includes both selected days in the browser's
local timezone and is converted to API `from` (inclusive) and `before` (exclusive)
instants. It selects workout start times; switching filters starts pagination again.
Invalid URL dates remain visible as validation errors. Invalid cursors, including
after a backend restart, offer a retry from the first page.

Account settings list browser/native sessions with current-device identification,
pagination, explicit refresh and individual/all revocation. Revoking the current
session, revoking all sessions, and a successful password change end the current
login and clear private caches. Password limits come from deployment policy.
Because the password endpoint also returns `unauthenticated` for an incorrect
current password, the client verifies `/me` before distinguishing that error from
an expired session. Password form values remain in component memory only.
Demo mode supports workout filters but exposes no account-management forms.

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
                 validated response ← backend (or explicit demo fixtures)
                     ↓
                 Svelte views → ECharts / route diagram
```

`contracts/web.config.ts` selects implemented browser authentication and Workout
operations and reuses the existing fetch generator. Its input adapter normalizes JSON media-type parameters
for Orval's Zod renderer. A pinned renderer adaptation uses Zod `guid()` to match
Haskell's UUID codec, which accepts canonical hex groups without restricting the
version/variant bits. Actual Servant response tests guard both compatibility fixes.

Each root layout owns its QueryClient. Query owns remote data and request
cancellation; Svelte owns filters, local selection and responsive presentation.
Errors expose safe user-facing messages rather than payloads. Revisions stay as
strings. DTOs are generated; presentation projections retain canonical field and
unit meaning. Metric averages and maxima come exclusively from the backend's
`calculatedSummary` for the current workout revision; device aggregates and chart
samples are never display fallbacks. The backend includes real zeros and computes
a time-weighted mean of linear segments between samples, excluding intervals over
120 seconds and performing no extrapolation. Extrema use all real samples.
A singleton has extrema but no mean; absent samples leave statistics unavailable.
Recorded time and distance remain available for manual and summary-only workouts.
Demo fixtures without calculated results deliberately show missing statistics.

ECharts draws elapsed-time samples without smoothing or bridging display gaps
over two minutes. This is an explicit rendering rule, not a pause detector or a
statistical calculation. A sample selector and table provide accessible values.
The route view is a schematic preview rather than a geographic basemap.

Zod is the default boundary validator. Effect remains approved for complex future
workflows but is not installed. Tailwind and shadcn/Bits UI remain available
choices for later features; this demo uses local CSS and semantic native controls.
Tabler Icons supplies the shared outline icon family through per-icon Svelte imports.

## FIT uploads

In connected mode, choose **上传 FIT** beside manual entry in the workout list.
Select one FIT activity and submit it; the server supports single-session cycling
and running files up to the limit advertised by `/auth/policy` (currently 16 MiB).
File bytes are sent directly through the same-origin API proxy with session/CSRF
protection. The server validates content; filename and browser MIME hints are not
trusted. Empty/oversized files are rejected locally as an early usability check.

The result distinguishes success, recorded parser failure, suppression and pending
processing. A successful result links to the workout. If a response is lost, the
selected file stays fixed for an explicit retry; owner-scoped byte deduplication
prevents duplicate publication. Leaving the page does not undo a committed import.
Imported workouts support the existing metadata editor and source-aware deletion.
Raw files are retained privately by the backend, never in browser persistence.
Demo mode has no upload form. Server archive setup is documented in
[backend architecture](../docs/backend-architecture.md#fit-upload-persistence).

Run `./scripts/web_integration_test import.spec.ts` from the repository root for
real HTTPS/backend/PostgreSQL upload checks at desktop and mobile widths. The
harness generates synthetic FIT fixtures and isolates both the database and archive.

## Code organization

Workout-specific views live in `src/lib/workouts/components/`; account and session
views live in `src/lib/auth/components/`. Shared dialog, icon, feedback and theme
controls remain in `src/lib/components/`. `workouts/chart-data.ts` prepares numeric
sample times/display points and performs binary nearest-sample lookup. These
values are cached by Svelte derivations independently of cursor and theme changes;
a cursor move updates chart markers without rebuilding the full series.

## Best-duration power

Cycling and running power analysis pages and dialogs request the owned workout's
`power-curve` endpoint. The backend supplies fixed durations from one second to
four hours with best mean watts and interval timestamps. The UI provides a
logarithmic duration chart, selection and a results table. It rejects mismatched
workout revisions and offers a refresh. Missing coverage is shown explicitly;
summary-only power still has an analysis entry, with a local unavailable message
and no power-curve request when its sample stream is empty. Demo rides/runs include a known
60-second, 200 W synthetic effort. Longer sparse observations do not fabricate
continuous efforts. No workout data is saved to browser storage.

Demo power-curve responses are static fixtures; they do not run the backend
calculation. Use connected mode to review the complete calculation flow.
`./scripts/web_integration_test power-curve.spec.ts` verifies cycling and running
on desktop and mobile against the real Haskell backend, using declining power
samples and checking both the API response and displayed best-duration values.

## Workout analysis and personal settings

Connected details keep the existing route and linked-chart controls, then show
backend power/running analysis, HR load, distance splits, recorded laps, and
source/context. Metric dialogs and direct pages expose the backend's statistics,
time distributions, zones and aligned relationships, including grade, temperature
and running dynamics when recorded. Statistics use the full backend input;
browser chart points never supply averages. Time plots retain every recorded
sample and insert breaks using `analysisMaxGapSeconds`. Relationships render the
backend's bounded point set. Units remain explicit in selectors, tables and axes.
Recorded altitude/energy/laps/bicycle context remain labeled separately.

`/settings` contains software, effective-dated body profiles, equipment and the
existing account/session controls. GET/PUT use owner-scoped generated contracts.
The editor captures a revision, preserves existing profile history, appends a
complete parameter snapshot, and keeps equipment identity/kind immutable.
A conflict retains the draft and requires an explicit reload. Save invalidates
analysis/history queries. Profile fallback selection and all HR/power rules are
backend-owned. The saved appearance applies when authenticated; the header picker
remains a local appearance override. Only appearance may use browser storage;
body profiles, equipment, workouts and completeness inputs stay in memory.

The HR-load section links to `/training-history`. The form sends 1–366 consecutive
local civil days with real UTC boundaries, explicit per-day recording completeness
(default unconfirmed), and either an explicitly chosen zero prior load or both
known CTL and ATL. Unknown results remain gaps, not zero. The results identify
the submitted inputs, method and settings revision. No fatigue algorithm runs
in the browser. Demo mode does not simulate these persisted features.

Targeted real-backend verification:

```sh
./scripts/web_integration_test preferences.spec.ts settings.spec.ts
./scripts/web_integration_test analysis.spec.ts power-curve.spec.ts
```

These use only synthetic data on desktop/mobile and check persistence after a
backend restart, profile history, equipment retirement, revision conflicts,
saved settings affecting selected analysis profiles and HRSS/W/kg, metric detail,
km/5 km splits, and unknown/rest/prior-load history behavior. Calendar tests cover
23/25-hour DST boundaries. Generated response validators also read the actual
Servant settings and analysis fixtures. Existing session, route, chart and import
controls retain their separate regression suites.
