# API contract

The v1 draft defines authentication, workouts, workout groups, imports and exports
for parallel web and iOS development. Its source is
[`Api.Types`](../backend/Api/Types.hs), with routes, request types and codecs
grouped by feature. The generated OpenAPI document is a build artifact.

**Implementation status:** the runtime mounts all eleven authentication routes,
including browser/native login, `/me`, session management and password change,
against PostgreSQL. The five core Workout routes support manual cycling/running data:
creation, list/detail, metadata edits and revision-checked deletion. The hello
probe remains available. HealthKit submission and import-detail routes are mounted;
they currently accept one cycling or running part per source object. Multipart
objects are rejected before publication; batch selection submits distinct objects.
Import state, owner-scoped UUID deduplication, explicit retry/refresh, and
source-aware workout deletion are durable.
HealthKit submissions have a per-process limit of 60 requests per owner per minute
and 600 total, returning `429` with `Retry-After: 60`. Authentication has a separate
budget. Horizontal deployment also needs a shared upstream rate limit.
FIT upload and shared import-detail reads are mounted for one cycling or running
activity per file. A separate process-wide admission limit is checked before FIT
POST body buffering (default 4, configured by `FIT_UPLOAD_SLOTS`, range 1–32).
Capacity exhaustion returns the existing `429 rate_limited` problem and
`Retry-After: 1`; clients may retry without changing the upload identity. This
limit also applies before authentication, independently of owner rate limits and
the two SDK/archive worker permits. Files are limited to 16 MiB, parsed synchronously, retained
privately, and deduplicated by owner and SHA-256 of actual input bytes. Invalid
or unsupported files return a durable `failed` import with no published workout.
Normal reupload returns the recorded state; explicit FIT retry/refresh and archive
management routes remain contracts. Source-aware deletion suppresses FIT imports.
Export receipt creation and listing are mounted with durable owner-scoped identity
and import-loop suppression. Other import routes, group routes and file export
routes remain contracts. Group filters currently have no matching memberships
and group cleanup is not implemented. The web client supports authenticated FIT upload. Contract tests use synthetic responses;
`make -C backend http-test` separately exercises actual authentication and Workout handlers
and HealthKit handlers against a fresh private PostgreSQL cluster. The rules below apply to each feature
as it is implemented.

## Single-workout power curve

`GET /api/v1/workouts/{workoutId}/power-curve` is implemented for cycling and
running. Authentication and owner isolation match the detail endpoint: no session
returns 401, and missing/other-owner workouts return 404. Responses use `no-store`.
The endpoint does not accept client-supplied durations or persist derived results.

The response is `PowerCurve`: `curveWorkoutId`, `inputRevision` (decimal string),
`method`, `maxGapSeconds`, and ascending `points`. Each point has integer
`durationSeconds` and an optional `best` containing `averagePower` in W and UTC
`start`/`end`. Absence of `best` means insufficient continuous coverage; zero watts
is a valid result. All configured points remain present, including unavailable
ones. Durations are 1, 5, 10, 15, 30 seconds and 1, 2, 3, 5, 10, 15, 20, 30, 45,
60, 90, 120, 180, 240 minutes.

Method `linear-best-duration-v1` integrates linear interpolation across sample
gaps at most five seconds, includes real zeros, and forbids windows crossing
longer gaps or extending beyond samples. Timer events do not compress elapsed
time. Ties within relative numerical tolerance 1e-12 select the earliest interval. Clients display a curve only alongside
the matching workout ID/revision; mismatches offer a workout refresh.

## Module relationships

```text
Workout/*/Types  <── Api/Workout/*/Codec
       ↑                     ↑
       └──────── Api/<feature>/Types
                             ↑
                     Api/<feature>/Routes
                             ↑
                         Api.Types
                             ↓
                        Api.OpenApi
                             ↓
                OpenAPI → TypeScript / Swift
```

Canonical `Workout`, `WorkoutObservation`, `WorkoutUserData`, `WorkoutGroup`,
`CyclingData`, `RunningData` and their measurement types are reused directly.
Canonical modules import neither HTTP nor OpenAPI. `Generic` derivation supports
codecs in separate modules; it does not change validation or persistence rules.

API-specific types describe different meanings: an authenticated session, a
creation request without server-assigned identity, an optimistic update, a
summary card, a paginated collection, or a group with its storage revision.
There is no parallel API copy of the cycling/running measurement records.

`Api.Auth.Context` associates `AuthProtect SessionAuth` with a server-only
`Principal`. The authentication handler validates credentials and supplies
that principal to private handlers. User identity is not an editable field of
every request. Owner-scoped persistence queries must use the principal.

## Common wire rules

All routes use `/api/v1`. JSON bodies use `application/json`; FIT upload/download
uses `application/octet-stream`. Canonical field names are retained, including
`workoutId`, `workoutObservation` and `observationSport`. API-specific fields drop
their Haskell leading underscore. Generated models establish exact field names.

| Concern | Contract |
| --- | --- |
| IDs | UUID strings, generated by the server except client-generated submission and source object IDs. Never infer ownership from a UUID. |
| Revisions | Unsigned decimal strings without leading zeroes, including `"0"`. Never coerce them to a JavaScript number. Revisions are scoped to their resource, not comparable across resources. |
| Times | RFC 3339 instants; responses emit UTC with `Z`, with up to 12 fractional second digits when present. Clients decode fractions within their native date precision. Query offsets are normalized to instants. Local-calendar/timezone settings are not modeled yet. |
| Optional fields | Omit absent fields. JSON `null` is rejected. Empty arrays mean no samples/members in an allowed empty collection; zero is a measured value. |
| Updates | `PUT` replaces the editable document. Omission clears an optional editable field. It never replaces the whole canonical observation implicitly. |
| Alternatives | Sport uses `{type, data}` with `cycling` or `running`. Record alternatives such as events/extensions have `type` alongside their named fields. Simple enums are strings, even when there is only one option. |
| Evolution | Readers tolerate unknown object fields; unknown enum alternatives are errors. Adding a sport/enum case requires coordinated client generation. This is a draft contract, not a promise to freeze every current field forever. |
| Validation | Decoding checks JSON shape; it does not prove domain validity. Application writes must run canonical and import validators before publication, then enforce ownership and concurrency transactionally. |

Time series are arrays of `{timestamp, value}`, each with its own sampling times.
No resampling, interpolation or alignment is implied. Measurement streams are
strictly increasing; ordered event streams may share timestamps. Empty streams
represent missing sensors. Independent cycling/running cadences retain their
distinct types. The baseline includes cycling HR/power/altitude/speed/cadence/GPS
and running HR/cadence/altitude/GPS, alongside the existing additional fields.

Canonical units are m, s, m/s, W, J, kg, °C, beats/minute, cycling rpm and total
running steps/minute. Coordinates are WGS84 latitude/longitude degrees. Grade
and percentage fields use percentage points, not fractions. Altitude is elevation
in metres; it can be negative. Recorded and calculated summaries remain separate;
calculated results carry input revision, method/configuration and calculation time.
Sport-level metric averages and extrema are calculated by the backend from canonical
samples, independently of recorded device statistics. Real zeros are included.
Means use time-weighted linear segments between adjacent samples at most 120 seconds
apart; longer gaps and extrapolation are excluded. Extrema use every actual sample.
Empty streams remain absent; a singleton has extrema without an average. This
calculation covers common sensor statistics, sport cadence and running dynamics,
not lap summaries, time/distance totals or training-load aggregates.
Creation, import publication/refresh and metadata edits persist current calculations.
Detail GET also persists missing or outdated calculations without advancing the
workout revision; repeated reads reuse the cache. List GET does not force backfill.
Clients display current calculated metric statistics and retain recorded time and
distance for manual or summary-only workouts.

## Authentication and ownership

Use username/password login and **one database session model with two credential
transports**. Each device gets a separate session. Native tokens are opaque, not
JWTs; v1 does not introduce an access-token/refresh-token pair.

| Client | Credential and lifecycle |
| --- | --- |
| Browser | `__Host-ai-fitness-session` cookie with `Secure; HttpOnly; SameSite=Lax; Path=/`, no Domain. Same-origin API/proxy deployment. Keep the CSRF token in application memory; never put the session secret in localStorage. |
| Native | `Authorization: Bearer <opaque token>`, returned once at native login and kept in Keychain. The same expiry, revocation and ownership rules apply. |

Generate session secrets with 256 bits of cryptographic randomness and store
only their SHA-256 digest. This fast digest is for random tokens; passwords use
Argon2id through a maintained implementation with configurable, measured cost.
Check session validity, idle/absolute expiry, revocation and account status on
every authenticated request. Reject requests carrying both session-cookie and
Bearer credentials instead of choosing one silently. The Bearer scheme name is
case-insensitive; the opaque credential remains case-sensitive.

Initial configurable session limits are browser idle 30 minutes / absolute 12
hours and native idle 7 days / absolute 30 days. Activity may extend idle expiry
but never absolute expiry. Responses expose both deadlines. Expired/revoked
credentials return `401`; clients return to login instead of inventing a refresh
flow. Logout revokes the current session; changing password and revoking all
sessions revoke the current session too.

The browser first calls `GET /auth/web/csrf`. This establishes a short-lived
anonymous bootstrap cookie or reuses the active browser session and returns its
CSRF token, with `Cache-Control: no-store`. Login rotates the session and CSRF
token. Unsafe cookie-authenticated requests require `X-CSRF-Token` and a matching
allowed `Origin`; registration and browser login have the same protection.
The native login route must reject browser-origin requests and session-cookie
credentials; this endpoint is for native clients. Native
Bearer requests do not require CSRF tokens. The shared protected-route header is
optional in OpenAPI because its requirement depends on credential transport;
server enforcement is mandatory for browser mutations.

Registration is explicitly enabled or disabled by deployment policy. V1 exposes
browser registration followed by a separate login; native users can sign into an
existing account. There is no email-based recovery contract yet; local admin
recovery is the initial operational path. Publish password length/upload limits
through `/auth/policy`; validate the same limits server-side. Login failures must
not reveal whether an account exists. Rate-limit authentication and imports;
return `Retry-After` seconds with `429`.

Private queries and mutations are scoped to `Principal.principalUserId`, including
every group member, import mapping and export receipt. A resource belonging to
another user returns `404`. A supplied workout ID, user-like unknown field or
source UUID never grants access. Sensitive responses use `Cache-Control: no-store`.
Do not log passwords, tokens, CSRF values, raw FIT bytes or complete health/GPS
payloads. MCP credential delegation/OAuth remains a separate future decision.

## Routes

The tables show success responses. All JSON operations share `Problem` errors;
the generated document lists exact request shapes, headers and query parameters.

| Method and path | Input | Success |
| --- | --- | --- |
| GET `/auth/policy` | — | 200 `AuthPolicy` |
| GET `/auth/web/csrf` | Browser cookie if present | 200 `CsrfToken`, cookie/cache headers |
| POST `/auth/web/login` | `Credentials`, CSRF header | 200 `WebSession`, cookie/cache headers |
| POST `/auth/native/login` | `Credentials` | 200 `NativeSession` |
| POST `/auth/register` | `Registration`, CSRF header | 201 `User` |
| GET `/me` | Session | 200 `User` |
| POST `/auth/logout` | Session | 204, clear browser cookie |
| GET `/auth/sessions` | Pagination | 200 `Page Session` |
| DELETE `/auth/sessions/{sessionId}` | Owned session ID | 204 |
| DELETE `/auth/sessions` | Current session | 204, revoke all |
| PUT `/auth/password` | `PasswordChange` | 204, revoke all |

| Method and path | Input | Success |
| --- | --- | --- |
| GET `/workouts` | Filters and pagination | 200 `Page WorkoutCard` |
| POST `/workouts` | `ManualWorkout` | 200 canonical `Workout` |
| GET `/workouts/{workoutId}` | ID | 200 complete canonical `Workout` |
| GET `/workouts/{workoutId}/power-curve` | ID | 200 `PowerCurve` |
| PUT `/workouts/{workoutId}/user-data` | `EditWorkout` | 200 canonical `Workout` |
| DELETE `/workouts/{workoutId}` | `expectedRevision`, `deleteEmptyGroups` | 204 |
| GET `/workout-groups` | Pagination | 200 `Page GroupView` |
| POST `/workout-groups` | `CreateGroup` | 200 `GroupView` |
| GET `/workout-groups/{groupId}` | ID | 200 `GroupView` |
| PUT `/workout-groups/{groupId}` | `EditGroup` | 200 `GroupView` |
| DELETE `/workout-groups/{groupId}` | `expectedRevision` | 204; workouts retained |

Workout lists include metadata, range and recorded/calculated sport summaries,
not sample streams. Detail returns the entire canonical object. `GroupView`
wraps the canonical group with a resource revision. Members are nonempty, unique,
ordered owned workout IDs; continuity is not required and a workout may belong
to multiple groups. Group metadata and ordering are user-owned.

| Method and path | Input | Success |
| --- | --- | --- |
| GET `/imports` | Pagination | 200 `Page ImportRecord` |
| POST `/imports/fit` | Raw FIT bytes | 200 `ImportRecord` |
| POST `/imports/healthkit` | `HealthKitSubmission` | 200 `ImportRecord` |
| GET `/imports/{importId}` | ID | 200 `ImportRecord` |
| POST `/imports/{importId}/retry` | `RevisionRequest` | 200 `ImportRecord` |
| POST `/imports/{importId}/refresh` | `RefreshImport` | 200 `ImportRecord` |
| DELETE `/imports/{importId}/archive` | `expectedRevision` | 200 `ImportRecord` |
| DELETE `/imports/{importId}/suppression` | `expectedRevision` | 200 `ImportRecord` |
| DELETE `/imports/{importId}` | `expectedRevision`, `deleteWorkouts`, `deleteEmptyGroups` | 204 |

Import records expose source identity, processing state, archive availability,
prior successful mapping and failure details. Filesystem paths and raw device
structures are not exposed. This is an import-status projection, not a canonical
Workout or a public copy of the persistence record.

| Method and path | Input | Success |
| --- | --- | --- |
| GET `/workouts/{workoutId}/exports/canonical` | ID | 200 `CanonicalExport` |
| GET `/workouts/{workoutId}/exports/fit` | ID | 200 FIT bytes, `Content-Disposition` |
| GET `/workouts/{workoutId}/export-receipts` | Pagination | 200 `Page ExportReceipt` |
| POST `/workouts/{workoutId}/export-receipts` | `RecordExport` | 200 `ExportReceipt` |
| GET `/workout-groups/{groupId}/exports/canonical` | ID | 200 `CanonicalExport` |

Canonical export includes version `canonicalV1`, export time, complete workouts
and groups. A single-workout export has one workout and no groups. A group export
contains that group and full members in group order. It reads canonical storage,
not source archives. FIT is a representable projection, not a lossless backup of
all canonical fields. Unsupported exports fail explicitly rather than returning
corrupt or misleading files.

Apple Health export runs on the device. Record a receipt only after its platform
write commits, identifying the exported workout revision and external object ID.
A receipt may describe a revision exported just before a concurrent edit; it
does not overwrite the current workout. Owner/platform/external-ID identity makes
retries idempotent; conflicting workout/revision associations return `409`.
Receipts support loop prevention, but do not implement HealthKit sync themselves.
The mounted Apple Health receipt endpoint requires a non-nil HealthKit object UUID
and a positive revision no newer than the current workout. UUID casing is normalized.
Historical receipt identities survive workout deletion; their owner-scoped source
objects remain suppressed on import. Receipt listing still requires a live owned
workout. The server records the client's acknowledgement; it cannot independently
inspect the device's HealthKit store.

## Pagination, filtering and errors

Collections use `cursor` and `limit`, default 50 and maximum 100. Invalid limits
return `400`, rather than silently clamping. `nextCursor` is absent on the last
page. Cursors are opaque and bound to owner, collection, filters and ordering;
reusing one with different filters is invalid. Pagination is not a historical
snapshot of concurrent edits; clients should deduplicate by resource ID.

Workouts order by observation start descending, then UUID descending. `from` is
inclusive and `before` exclusive, filtering the workout **start**, not interval
overlap. `sport` is `cycling` or `running`; `tag` matches a complete tag and
`groupId` restricts membership. Other collections order by creation time then ID,
both descending; receipts use export time then ID. Group member order is always
the explicit user order, independent of list order.

Errors use `{code, message, requestId, fields}`. `fields` is an array of
`{path, code, message}`; body paths use JSON Pointer and query paths identify the
parameter. Clients branch on `code`, not localized/human-readable messages.

| HTTP status | Meaning and representative codes |
| --- | --- |
| 400 | Malformed request, invalid query/cursor/revision syntax: `invalid_request`, `invalid_query`, `invalid_cursor` |
| 401 | Missing, invalid or expired credentials: `unauthenticated`, `invalid_credentials` |
| 403 | Valid session but forbidden action, CSRF failure or disabled registration: `forbidden`, `csrf_failed`, `registration_closed` |
| 404 | Absent or unowned resource: `not_found` |
| 409 | Stale revision, idempotency conflict or incompatible import state: `revision_conflict`, `submission_conflict`, `reconciliation_required`, `archive_missing`, `empty_group` |
| 413 | Configured input-size limit exceeded: `payload_too_large` |
| 422 | Structurally valid input violates domain rules: `validation_failed` |
| 429 | Rate limited: `rate_limited`; `Retry-After` gives seconds |
| 500 | Unexpected failure without internal details: `internal_error` |

The default response also uses `Problem`, including transport failures such as
unsupported media type. FIT download uses JSON errors and binary success.
Implementing the contract requires Servant error formatters and WAI exception/auth
handling as well as typed handler responses; default Servant errors alone do not
meet this rule. No-content responses contain no JSON body.

## Revisions, retries and import publication

Every edit/delete supplies the expected resource revision. A stale value returns
`409` with no partial changes. Workout observation or metadata changes advance
the workout revision; group edits/membership changes advance the group revision;
import state changes advance its separate revision. The database must recheck
these guards within the transaction.

Manual workout and group creation use client-generated `submissionId`. Retrying
the same owner/operation/submission and content returns the same resource ID
with `200` (the current resource view); different content returns
`submission_conflict`. Persist identity/tombstones so a retry cannot resurrect a
deleted object. These IDs are request identity, not workout identity.

FIT deduplication uses SHA-256 of actual input bytes, scoped to the authenticated
owner. HealthKit uses the owner's source object UUID. A normal repeated successful
import returns the existing complete mapping; it does not replace observations
or match workouts by time. There is no cross-source merging. A source with several
supported sports publishes several workouts and their group in one transaction.

Imports run synchronously initially. `200` acknowledges the returned import
state, **not necessarily successful workout publication**. Check `status`:
`succeeded` means all canonical output and index state committed durably;
`failed` carries a recorded failure and may retain a previous success; an already
active request can return `processing`; suppressed sources stay suppressed.
Clients may read the import status again. Do not add an automatic background
job system just to satisfy these state representations.

Archive FIT bytes privately before publishing success, and retain them by default.
Removing an archive retains canonical data and its import index. Retry and refresh
require the retained FIT archive; missing bytes return `archive_missing`. Reupload
of identical bytes may restore the archive, but does not implicitly refresh an
existing workout or override suppression. Normal imports never retry a failed
attempt silently. Retry applies only to a failed import with no previous
publication. After a failed refresh, use refresh again with all expected revisions;
a revision-free retry returns `409 refresh_required`.

FIT refresh supplies the import revision and every published workout revision.
HealthKit `normal` submission omits `expectedRevision` and has empty
`expectedWorkouts`; `retry` requires the import revision and no expected workouts;
`refresh` requires both the import revision and all published workout revisions.
Invalid combinations return `422`. Parts have unique, source-stable `partKey`s.
Adapters normalize units and timestamps, then the backend validates and assigns
identity. Client-supplied calculated summaries must be rejected on publication;
only backend calculations can establish trusted calculated results.

Refresh maps stable part keys back to existing IDs, retains all user content and
group ordering, and invalidates calculated summaries. Missing/new parts, changed
group membership or any stale revision reject the whole batch. Recheck the
stored group state alongside all revisions in the publication transaction.
Structural reconciliation remains an explicit later capability; v1 reports
`reconciliation_required` instead of guessing or creating replacement records.

Deleting a workout detaches it from every group and suppresses its source import
so ordinary synchronization cannot restore it. Surviving workouts from that
source remain. If a group would become empty, reject unless the required
`deleteEmptyGroups` flag is true. Deleting an import suppresses its source and
removes its archive; the required `deleteWorkouts` flag controls canonical output
deletion. Keep the suppressed index/tombstone. Prior-success mappings are history
and can refer to deleted outputs; they do not prove those outputs still exist.
Clearing suppression changes permission to import, not canonical data; it does
not automatically recreate deleted members or bypass reconciliation.

HealthKit adapters advance checkpoints only after durable acknowledgement or
explicitly handled suppression/deletion, never on HTTP success alone. Associated
sample/route refresh, source deletion and export-origin filtering remain adapter
responsibilities. An anchor is not a backup and cannot recover deleted payloads.

## Generation and verification

From the repository root, inside `nix develop`:

```sh
make -C backend check test contract contract-test format-check lint all
cd contracts
npm ci --ignore-scripts
npm run generate
npm run check
```

On macOS with the project's Swift 5.10/Xcode toolchain, from the repository root:

```sh
cp contracts/build/openapi.json contracts/swift/Sources/ContractClient/openapi.json
swift test --package-path contracts/swift --disable-automatic-resolution
```

SPM dependencies are locked in `Package.resolved`; first use may fetch the locked
packages. Create Swift clients through `makeFitnessClient(serverURL:transport:middlewares:)`
in `ContractClient.swift`. It supplies the date transcoder for whole and fractional
seconds; the generated initializer's default configuration does not accept both.
The Swift tests call this client through a fixture transport with the same Servant
payloads, checking response decoding, fractional times in query/body encoding,
invalid dates, sport alternatives and large revision strings. This is a macOS
contract check, not an iOS simulator/device or HealthKit test. TypeScript checks
compile strict consumer code, validate actual payloads against the schema and
exercise generated fetch with a fixture transport.
Kotlin and Go generation/compilation remain their respective client tasks.

The pinned Haskell library generates OpenAPI 3.0. `contracts/openapi.mjs` performs
an explicit 3.1 Schema Object conversion, handling nullable types, exclusive
bounds and UTC formats while preserving examples and integer literals exactly.
It rejects unsupported tuple schemas. Header-bearing UVerb responses and unary
optional event fields need small, tested library compatibility corrections in
the Haskell schema modules. Singleton enum encoding is made explicit in the JSON
codec. These workarounds are tied to the pinned toolchain and should be removed
only after an upstream upgrade passes the same regressions.

The maintained inputs are Servant/canonical types, codecs, generator configuration,
tests and dependency locks. Do not edit generated specifications or client code.
OpenAPI and TypeScript outputs are compared across two clean output directories;
Swift generator/runtime versions are pinned and compiled. All derived outputs
and dependencies are ignored by Git. The pinned Orval fetch template also needs
the small `fetch-client.ts` binary-body/response and header adaptations; it fails
generation if the expected templates change. Headers are merged with `Headers`
so record, tuple-array and `Headers` inputs work, and request options override
generated headers case-insensitively. Tests cover these inputs and overrides,
exact upload/download bytes, JSON download errors and the explicit CSRF header.
No CI workflow or production transport is introduced in this contract change.

Analysis, recommendations, training plans, Bike management and MCP authorization
do not have placeholder APIs here. Define each contract when its product behavior
is decided. The next implementation slice can now implement authentication and
owned workout persistence while clients consume this shared draft.
