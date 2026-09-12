# AI Fitness — Haskell Backend Architecture

## Purpose and implementation status

AI Fitness uses Haskell for its backend, with IHP, Servant, and PostgreSQL as
the architectural foundation.

**IHP provides infrastructure, Servant defines the API, and business logic stays
independent of HTTP and framework controllers.** The backend is not intended to
be a traditional IHP MVC application. SvelteKit provides the separate web UI.

This is the current, evolving architecture, not a permanent constraint or an
instruction to implement every capability at once. Revisit decisions when
requirements or evidence change. Update this document and affected usage
instructions alongside implementation changes so they describe the same system.
Discuss material changes in direction with the project owner before implementing
them; a separate ADR is not required unless requested.

The runtime uses IHP configuration, Warp on localhost, and a bounded Hasql pool.
Servant mounts authentication, manual Workout CRUD and the existing hello probe. Browser
and native credentials share PostgreSQL sessions; the API performs ownership,
CSRF and expiry checks explicitly. Request bodies are bounded and errors use the
shared `Problem` shape. No request headers, credentials or health payloads are
logged. The full contract also describes features that are not mounted yet; see
the [API contract guide](api-contract.md) for the current implementation scope.
Migrations are applied separately before startup; the server never starts a
PostgreSQL process or silently changes its schema.

## System overview

```text
SvelteKit ─┐
           │
iOS ───────┼── HTTP / OpenAPI contract ──> Servant API (/api/v1/*)
           │                                      │
Go MCP ────┘                               Domain operations
                                                  │
                                  Infrastructure / PostgreSQL

IHP supplies the backend runtime, configuration, lifecycle, database
infrastructure and required WAI middleware around this flow. The API's explicit
session model owns authentication independently of IHP MVC sessions.
```

| Component | Responsibility |
| --- | --- |
| IHP | Backend runtime and shared infrastructure |
| Servant | External HTTP API types, routing, handlers, and authentication boundary |
| Domain | Canonical models, business rules, and calculations |
| Import | Single-source decoding, normalization, input identity and explicit refresh |
| PostgreSQL | Persistent storage and database-level integrity |
| OpenAPI | Shared API contract for web, iOS, and MCP clients |
| SvelteKit | Independent web frontend |

## IHP: runtime and infrastructure

Use IHP for the infrastructure needed by the backend:

- PostgreSQL integration and Hasql database infrastructure.
- Connection pooling.
- Schema management and migrations.
- Application lifecycle and configuration.
- Session persistence infrastructure where compatible with the API session model.
- Nix development environment support.
- Required WAI middleware.

IHP HTML views, HSX pages, and large collections of MVC controllers are not core
application building blocks. IHP is not the primary router for client APIs.
Reuse its infrastructure without making domain models depend on IHP controller
or request contexts.

## Servant: API boundary and contract

All formal client APIs use Servant, under a versioned API namespace such as
`/api/v1/*`. Servant API types are the primary source of truth for the HTTP
interface. For example:

```haskell
type WorkoutAPI =
    "api"
        :> "v1"
        :> "workouts"
        :> Capture "id" WorkoutId
        :> Get '[JSON] Workout
```

This is an illustrative API shape, not an implemented endpoint or a finalized
workout model.

The intended contract flow is:

```text
Servant API types
       │
       ▼
OpenAPI 3.1
       ├── TypeScript client → SvelteKit
       ├── Swift client      → iOS
       └── Go client         → MCP adapter
```

Do not maintain independent handwritten API definitions for each client.
Derive the specification and client types where possible. OpenAPI 3.1 is the
target contract version. The implemented pipeline derives 3.0 from the pinned
Servant library, converts Schema Objects to 3.1, and verifies encoded canonical
responses against the specification and generated TypeScript/Swift consumers.
The [contract guide](api-contract.md#generation-and-verification) documents the
tested compatibility corrections and the checks still required for other clients.

`Api/<feature>/Types` declares request/response projections, while
`Api/<feature>/Routes` declares HTTP operations. Canonical workout records are
shared directly and their JSON/schema instances live in `Api/Workout/*/Codec`.
`Api.Types` composes public authentication and session-protected product routes;
`Api.application` composes only the implemented route groups using the same aliases.

## Domain: workout data and operations

The current model follows the v3 import/sync boundary, with the 2026-09-11
Workout/WorkoutGroup decision superseding its native multisport representation.
It separates canonical observations, user-owned content, derived results, and import state.
Only cycling and running are modeled; other sports are added when needed.

Cycling and running are developed together. Their initial measurement baseline is:

| Sport | Baseline time series |
| --- | --- |
| Cycling | Heart rate, power, altitude, speed, cycling cadence, GPS position |
| Running | Heart rate, running cadence, altitude, GPS position |

This is a capability baseline, not a requirement that every workout has every
sensor. Existing additional measurements remain supported. Altitude is stored as
timestamped elevations, preserving rises and falls for later analysis. The shared
`Workout.Sport` operations expose heart rate, power, speed, altitude and position;
cycling and running retain their own cadence types and units.

```text
Workout (UUID, revision)
├── WorkoutUserData: title, notes, tags, statistics inclusion
└── WorkoutObservation
    ├── TimeRange
    ├── Sport: Cycling CyclingData | Running RunningData
    │   ├── independent metric streams
    │   ├── reported and computed summaries
    │   └── typed Lap summaries and boundaries
    ├── events and course points
    ├── athlete context at the time of the workout
    └── extensions and data-quality notes

WorkoutGroup: UUID + user-defined ordered NonEmpty WorkoutId membership
```

Each Workout records exactly one sport. Sport is the typed measurement payload;
Workout adds identity, revision, time range and user content. There is no
WorkoutSegment or duplicate observation-level summary: summaries live in the
cycling/running payload and its laps.

A source that explicitly represents several sports produces separate Workouts
linked by a WorkoutGroup. No transition workout is inferred. An eventual adapter
must explicitly handle unsupported source sports rather than silently discard or
mislabel them. Independent files are not automatically combined. Users can also
associate existing workouts for joint analysis. Group membership need not be
temporally continuous or exclusive to one group, but cannot contain duplicate
IDs. Resolving member existence remains a persistence/application responsibility.

### Modules and validation

| Module | Responsibility |
| --- | --- |
| `Workout.Identity.Types` | UUID identities and workout revision |
| `Workout.Measurement.Types`, `.Summary`, `.Validation` | Units, time series, generic statistics/laps/extensions, shared operations and validation primitives |
| `Workout.Common.Types`, `.Empty`, `.Validation` | Shared motion/environment data and common summaries |
| `Workout.Cycling.Types`, `.Empty`, `.Validation`, `.Update` | All cycling-specific data, initial values, checks and calculated-summary invalidation |
| `Workout.Running.Types`, `.Empty`, `.Validation`, `.Update` | All running-specific data, initial values, checks and calculated-summary invalidation |
| `Workout.Sport.Types` | Sport sum type and type re-exports |
| `Workout.Sport`, `Workout.Sport.Validation` | Thin dispatch to the relevant sport operations |
| `Workout.Types` | Workout, observation, user content, group and event types; type import entry point |
| `Workout.Empty` | Workout-level initial values and convenience re-exports |
| `Workout.Validation.Types`, `Workout.Validation` | Error types and workout/group validation orchestration |
| `Workout.Update` | Revision-checked observation/user updates |
| `Import.Types`, `Import.State` | Input identities, single/grouped output mappings, latest attempt, prior success and retry planning |
| `Import.Output` | Output validation and revision-checked batch refresh by stable source-local part identity |

Cycling and running modules do not import each other or the aggregate
`Workout.Types` entry point. Both depend on Common/Measurement, and Sport
provides the small dispatch layer. Adding a cycling rule should normally touch
only `Workout/Cycling/`, not running or workout-level logic.

Types modules contain declarations only. Operation modules depend on types;
`Workout.*` never imports `Import.*`. UUID representation uses `uuid-types`;
identity generation and database ownership are not implemented here. Each module
lists its public exports explicitly. Import identity/output validation returns
`ImportKeyError`/`ImportOutputError` constructors rather than free-form messages;
presentation of these failures belongs at the future transport boundary.

`TimeSeries a` remains a synonym for `Vector (Timed a)`. Each stream preserves its
own absolute UTC sampling timestamps. Validation requires strictly increasing
measurement timestamps, finite in-range values, and timestamps inside the owning
workout. Empty streams represent missing data. Cumulative distance (from workout
start) and metabolic energy cannot decrease. Position uses WGS84 degrees; speed
is m/s, distances m, duration seconds, energy joules, mass kg, temperature Celsius,
cycling cadence rpm, and running cadence total steps/minute. Import adapters must
normalize source cadence conventions and calorie/kJ units explicitly.

Event sequences, including gear changes, permit equal timestamps and preserve
input order. They are not constrained as strictly increasing metric streams.
Lap ranges must be positive, ordered, non-overlapping and inside their workout;
they need not cover the whole workout. Negative altitude and grade and real zero
power/cadence/torque values are valid. Suspicious values can carry canonical
`DataIssue` notes without replacing observations with zero or missing data.

Constructors are public for explicit record construction and editing. Types alone
do not enforce every invariant: adapters and application writes must invoke
validation. These are candidate data types, not proof-carrying validated values;
public constructors intentionally support normalization and explicit record edits.
The implemented update functions validate the resulting candidate. A future
wire decoder must pass through the same validation boundary before publication.
There is no silent sorting, resampling, unit conversion or outlier filtering in
validation. Algorithm-specific gap handling is a later analysis responsibility.

### FIT field coverage in the current structure

These are representation capabilities, not evidence that a FIT importer exists.
The test fixture combines the supplied summary values with synthetic sparse
samples; it is not decoded from the user's actual FIT file.

| Supplied field category | Representation |
| --- | --- |
| Sport and start/end | WorkoutObservation Sport and TimeRange |
| Elapsed, timer, moving duration | Separate optional CommonSummary durations |
| HR, power, speed, cumulative distance, GPS | Independent MotionData streams and typed statistics |
| Cadence | Distinct CyclingCadence / RunningCadence units and summaries |
| NP, TSS, IF | Separate optional typed summary values |
| Mechanical work and metabolic energy | Separate Energy fields; cumulative metabolic energy stream |
| Altitude, ascent/descent, grade, temperature | Streams and separate summary fields |
| Left/right balance and pedaling dynamics | Decoded left percentage plus separate left/right streams and summary values |
| Weather | Independent wind speed, wind-from bearing and relative-humidity streams |
| Gearing | Timed GearChange values with optional front/rear index and tooth count |
| Timer, battery, reminder, user events | WorkoutEvent ADT; equal-time events retained |
| Laps | Lap with range, label, reported/computed sport summary and extensions |
| Route markers | CoursePoint name, position, optional timestamp and kind |
| Athlete and bicycle profiles, FTP | Per-workout athlete context and per-cycling-workout context |
| Device identity, version, connection | ImportRecord.importedDevices, outside Domain |
| Custom fields | Namespaced numeric/text/boolean extensions with optional units; definitions can exist with no samples |

Extensible numeric values must already have a documented canonical meaning and
unit when used by business analysis. This is not a container for opaque FIT bytes
or a claim of lossless storage of every possible vendor field. v3 retains source
files so unknown fields can be addressed later rather than forcing a universal
schema now.

### Reported values, computed values and user changes

`Summaries a` preserves reported observations independently from an optional
computed result. Computed results carry their input workout revision, algorithm
name/version, configuration identifier and calculation time. Validation rejects
stale input revisions. No analysis algorithms are implemented yet.

`replaceObservation` receives an expected revision and a candidate observation.
It retains identity and user content, increments the revision, invalidates all
computed summaries (including lap summaries), and validates the candidate. A
failed replacement returns an error without mutating the existing value.
`replaceUserData` uses the same revision discipline. Database writes must still
check the expected revision transactionally; a pure function cannot resolve a
race between concurrent writers.

## Import, retention and reprocessing (v3)

```text
single-source input -> decode / normalize / validate -> Canonical Store
         |                                              |
         +-> FIT archive + owner-scoped Import Index     +-> read / analyze / export
                      |
                      +-> explicit reparse -> update existing observations
```

There is no cross-source sensor fusion or automatic brick composition. Same
start time is not identity. FIT identity is SHA-256 of actual input FIT bytes;
HealthKit identity is its owner-scoped object UUID, with explicit refresh support.
A database unique constraint on owner and source identity is required. The current
`ImportKey` and planner express that identity but do not implement hashing,
transactional claims, persistence or concurrency control. A separate minimal FIT
decoder exists below; it is not yet wired to the import planner or publication.

`ImportRecord` stores an optional archive path, last successful output/version,
latest attempt state, suppression timestamp and device metadata. `recordFailure`
retains the prior successful mapping/version. `planImport` returns an existing
successful result for a normal repeated import, allows explicit retry/refresh,
waits on a processing attempt and respects suppression. Stale processing-attempt
recovery and clearing suppression require explicit application policies.

An `ImportOutput` maps an input to either one Workout or a WorkoutGroup with
multiple Workouts. Each member has a stable `ImportPartKey` scoped to that input;
adapters must derive it from source-local identity, not sport, start time or a
fresh enumeration after filtering. A normal repeated import returns the complete
existing mapping, including the group ID.

`refreshOutput` matches candidates by part key and stored records by WorkoutId,
preserving IDs, user content, group title/notes and user-defined member order.
Changed part sets or group membership require explicit reconciliation. Any
revision conflict or invalid candidate rejects the entire proposed batch. This
function prepares pure values only: the application must publish all workouts
and the successful import mapping in one transaction, rechecking revisions and
group state at the write boundary. Initial ID/group creation, reconciliation,
and persistence are not implemented yet.

Archive successful FIT files by default until user deletion or explicit cleanup.
Store them privately and reliably before publishing database success. Ordinary
reads, analysis and canonical exports do not reopen the raw file. Reparse is an
explicit operation for new fields or corrected interpretations. Raw data is not
a backup of user changes; deleting raw removes backfill capability, not existing
canonical data. This supersedes the earlier `raw transient` rule.

HealthKit anchors and export mappings remain adapter state. Advance an anchor
only after acknowledged durable publication; account for associated sample/route
refresh and deletion, and prevent import/export loops. These protocols, database
constraints, archive IO and platform integration are **not implemented** by this
data-model change. v3's end-to-end sync acceptance cases remain future gates.

### Open-source evidence

Inspected on 2026-09-09; links refer to mutable upstream branches. We used ideas
and field semantics, not copied implementations:

- [GoldenCheetah FIT importer](https://github.com/GoldenCheetah/GoldenCheetah/blob/master/src/FileIO/FitRideFile.cpp): separate weather/gearing/extension series motivated separating continuous measurements from events and typed extensions.
- [ActivityLog2 schema](https://github.com/alex-hhh/ActivityLog2/blob/master/sql/db-schema.sql): distinct section summaries, laps, trackpoints and gear-change events informed the decomposition. It also archives raw input, unlike the earlier transient-raw proposal.
- The user-supplied v3 research document provides the current import/sync boundary. Its full platform and transactional claims have not been integration-tested in this repository.

## Verification

Inside the development shell, run `make check test` in `backend/`. Strict GHC
compilation covers every domain/import module, including modules not yet reached
by the current HTTP handlers. The standalone test runner covers canonical validation,
representative cycling data, running, single/grouped import outputs, group membership,
revision conflicts, reported-value preservation, cache invalidation, batch refresh identity matching, retry and
suppression decisions. `make` still builds the existing API. This validates pure
model behavior; it is not a FIT, database, HealthKit, export or performance test.

Tests are grouped into workout, cycling, running, import-state and import-output modules with a
small shared runner. `make format` applies the adopted Fourmolu configuration;
`make format-check lint` checks formatting and HLint suggestions. Fourmolu and
HLint use the existing pinned Nix toolchain; Haskell2010 and strict GHC warnings
remain in place. Refactoring preserves validation order and import decision
precedence, including suppression before active attempts.

## Database and integrity

PostgreSQL is the primary persistent database. `Storage.*` uses the Hasql version
supplied by IHP. Its operations compose as `ExceptT StorageError Transaction`.
Queries are declared with `hasql-th` quasiquoters, which check SQL syntax at
compile time and generate parameter/result codecs from explicit PostgreSQL type
and nullability annotations. Pure profunctor mappings adapt those codecs to
application types. `maybeStatement`, `singletonStatement`, `vectorStatement`,
`resultlessStatement` and `rowsAffectedStatement` preserve the intended result
cardinality. This does not check the live database schema or replace PostgreSQL
integration tests.
The root flake pins `hasql-th` 0.5 by source hash because the package set's older
0.4 release excludes the existing Hasql 1.10 API; the toolchain and flake lock
remain unchanged.
`Storage.Database.transaction` converts that composition into a Hasql `Session`
that can run in IHP's pool; `withConnection`/`runTransaction` supply a bracketed
connection for CLI and integration tests. `App.Environment` owns the HTTP pool. Time, IDs, password hashes and token digests are explicit
inputs; storage transactions do not generate secrets or run SDK/network work.
Revocation also samples the database clock at the write and never precedes a
session's creation time, including when a concurrent login won the account lock.

| Table | Durable contents and constraints |
| --- | --- |
| `users` | UUID, exact case-sensitive unique username, Argon2id PHC password hash, creation/disabled timestamps. Password verification belongs to `Auth.Password`; the SQL prefix check does not prove a hash is valid. |
| `sessions` | UUID, optional user FK, unique 32-byte token digest, transport, optional CSRF digest, device name, creation/activity/expiry/revocation timestamps. Anonymous sessions are allowed only for browser CSRF bootstrap; native sessions require a user. |
| `workouts` | UUID, owner FK, positive integral `NUMERIC` revision, storage version, canonical observation and user data in separate JSONB columns. Owner/ID and exact start-key indexes support scoped retrieval and pagination. |
| `workout_submissions` | Owner/submission identity, request digest and nullable owned-workout reference. Deletion retains the submission as a tombstone, preventing retries from recreating the workout. |

There are no separate tables per sensor or sport. Storage version 1 reuses the
existing canonical JSON codec in `Api.Workout.Codec`, without duplicating cycling
or running models. It stores the complete supported observation, including
independent sample times, events, laps, extensions and reported/calculated
summaries. The split columns preserve field ownership; JSONB is not an untyped
public update interface. Sample/range timestamps remain in canonical JSON and
retain their precision; account/session `TIMESTAMPTZ` metadata uses PostgreSQL's
microsecond precision. Revisions pass through decimal text and PostgreSQL NUMERIC,
so values above int64 round-trip without a narrowing conversion.

The database enforces identity, uniqueness, foreign keys, expiry ordering and
basic JSON shape. `Storage.Workout` applies canonical validation before writing
and after decoding stored payloads. Unknown storage versions and invalid stored
workouts fail explicitly. Changing a required field or JSON codec requires a
deliberate storage migration/version decision; importer reprocessing is separate.
The persistence boundary rejects U+0000 in canonical text with field validation
errors before writing JSONB; it never strips user content to fit PostgreSQL.

Every workout read/update takes an owner and includes it in SQL. Other users get
the same absence result as a missing workout. Updates lock the owned row, apply
the existing pure `Workout.Update` rules, and write with owner, ID and expected
revision predicates. They preserve the other field owner's content, increment
the revision and invalidate calculated summaries. These checks are application
query isolation, not PostgreSQL RLS. Mounted handlers derive ownership from an
authenticated `Principal`, never from a request's claimed user ID.

The transaction boundary uses Read Committed and explicitly condemns a transaction
on `Left`, rolling back earlier writes in a composed operation. SQL failures also
roll back; public storage errors contain neither SQL parameter dumps nor health
payloads. Session lookup enforces creation time, idle/absolute expiry, revocation
and account status. A returned anonymous bootstrap session is not a Principal.
`Auth.*` implements credential verification, login rotation and bounded idle
extension; `Api.Auth.Handlers` connects those operations to the shared contract.

`backend/Application/Migration/` is the authoritative schema history. `make migrate`
runs the pinned IHP migration tool against `DATABASE_URL`, applying each
file and its `schema_migrations` revision in a transaction. Run a single migration
process before serving traffic. Do not maintain a second hand-edited Schema.sql
or automatically migrate on HTTP startup. [IHP migration behavior](https://ihp.digitallyinduced.com/Guide/database-migrations.html)
was checked against the pinned implementation.

`make storage-test` starts a private disposable PostgreSQL instance, applies the
migration twice, checks failed-migration rollback, exercises actual Hasql queries,
constraints, ownership and simultaneous revision updates, then restarts PostgreSQL
and reads durable data again. It does not touch a configured development database.
The HTTP suite additionally verifies manual-submission idempotency, exact
pagination, owner isolation, edits and deletion tombstones. Groups, import indexes
and export receipts remain subsequent work.

## Authentication

The agreed contract uses username/password login and one opaque database-session
model per device. Browsers use a Secure/HttpOnly cookie with CSRF and Origin
checks; native clients use a Bearer credential stored in Keychain. Sessions have
idle/absolute expiry and explicit revocation, and passwords use maintained
Argon2id verification. No JWT access/refresh pair or MCP credential policy is
implicitly introduced.

`AuthProtect SessionAuth` supplies a server-only `Principal` to owned-resource
handlers; request bodies do not establish user identity. Every persistence query
must enforce ownership. The [API contract](api-contract.md#authentication-and-ownership)
defines login/bootstrap, expiry, logout, registration and authorization behavior.
All eleven authentication routes are mounted. Runtime configuration and the
transaction boundaries are described in [Authentication runtime](#authentication-runtime).

## FIT parsing

FIT parsing is a backend capability with an in-process integration boundary:

```text
Haskell
   │ FFI
   ▼
C ABI wrapper
   │
   ▼
Garmin C++ FIT SDK
```

The initial integration is implemented in `backend/Import/Fit.hs`, with separate
`Decode`, `Normalize`, and `Types` modules and `backend/native/fit_adapter.*`.
`readFit` performs a bounded local read, `decodeFit` calls the SDK in `IO`,
and pure `normalizeWorkout` constructs and validates a `WorkoutObservation`.
It does not create IDs, update import state, archive inputs or publish records.

The [official Garmin C++ SDK](https://github.com/garmin/fit-cpp-sdk) is pinned to
21.214.0, commit `37cc1743e6b4e9e1642f1cbc83a6cf0c49632931`, with a fixed source
hash in the root flake. Nix builds a static library and retains upstream license
text; the project does not vendor or modify SDK code. `pkg-config` supplies SDK
headers and platform-specific C++ runtime linkage to Make and Cabal.
The current Make build passes SDK libraries through GHC's `-optl` flags so they
participate only in final linking: storage query Template Haskell does not need
FIT symbols, and the macOS GHC interpreter cannot load the static SDK archive.

The C ABI owns an opaque result and exposes borrowed fixed-width numeric rows.
The header documents units, missing-value representation and allocation/free
ownership. C++ catches exceptions and emits bounded status codes, without source
data in logs. Haskell copies values before `bracket` releases native storage.
Missing SDK values become `Nothing` or absent samples. FIT device-relative times
are rejected, not interpreted as UTC. SDK scale/offset conversion happens once;
canonical constructors and domain validation remain in Haskell.

This subset requires a single cycling or running session in an activity file. It maps
session start/end, reported elapsed/timer duration and distance, and records for
heart rate, power, speed (enhanced preferred), cumulative distance, cadence,
altitude (enhanced preferred) and GPS. It leaves
other fields unmapped, including laps, course points, events and extensions. It rejects
other sports, multi-session files and non-activity files explicitly; it never selects
one session silently. Duplicate or out-of-range sample timestamps fail existing
domain validation rather than being sorted, dropped or interpolated.

`FitSport` preserves the source session sport through decoding; `normalizeWorkout`
selects the existing Cycling/Running constructors and shares only the common
motion/summary mapping. Running dynamics and derived results stay empty.
Cadence prefers `cadence256`; otherwise it combines `cadence` and optional
`fractional_cadence`, requiring the integer field. Cycling retains cycles/minute;
running doubles it to total steps/minute, per [Garmin's cadence explanation](https://forums.garmin.com/developer/fit-sdk/f/discussion/288454/fractional-cadence-values).
GPS requires a complete pair and converts signed semicircles to WGS84 degrees.
Enhanced altitude takes precedence, and below-sea-level values remain valid.
The C ABI summary has six doubles (including a sport discriminator); each record
has nine. Both sides and the native regression harness share this documented layout.

CRC/integrity and exact file length are checked; truncated and concatenated files
are rejected. Limits are 16 MiB, 100,000 records and 250,000 total messages. A
`safe` FFI call allows other Haskell threads to run, but cannot promise prompt
cancellation of native CPU work or a hard timeout. The adapter tests and limits
do not establish complete SDK memory safety or production upload readiness.

`make fit-test` runs SDK-encoded synthetic fixtures through the full Haskell
path. `make native-sanitize` runs allocation, invalid input and borrowed-buffer
checks with ASan/UBSan on project-owned C++ code; the SDK static library is not
instrumented. Real private files are optional local checks, kept outside all
worktrees and never committed or embedded in fixtures. The test harness prints
only outcomes/error categories for private inputs. See README for commands.

Do not design FIT ingestion around spawning a separate parser CLI or subprocess.
The native fixture generator and test harness are development tools only.

## Background work

IHP provides job infrastructure, but the first stage should keep operations
synchronous where practical:

```text
Request → Parse → Validate → Store → Calculate → Response
```

Introduce background jobs only when there is a demonstrated need: slow FIT
parsing, expensive calculations, unacceptable request latency, retries, or
asynchronous batch processing. Avoid introducing eventual consistency and job
state management before those requirements exist.

## Project boundaries

The backend may evolve toward the following conceptual structure:

```text
backend/
├── Api/
│   ├── Workout.hs
│   ├── Health.hs
│   └── Recommendation.hs
├── Workout/
│   ├── Types.hs
│   └── Sport.hs
├── TrainingLoad/
├── MuscleFatigue/
├── Infrastructure/
│   ├── Database/
│   ├── Auth/
│   ├── Storage/
│   └── Fit/
└── Application/
```

Group business modules by topic, with type definitions in modules such as
`Workout.Types`, and operations in focused modules such as `Workout.Sport`,
rather than requiring a `Domain` directory. Domain still
describes their responsibility and dependency boundary. The remaining layout is
illustrative; create modules as concrete features need them.

The monorepo uses one root Nix flake and lock file. Backend Haskell dependencies
use IHP's package set; other directly selected development tools use a recent
stable Nixpkgs release. Preserve upstream transitive dependencies where required
for IHP compatibility.

## Technology choices

| Area | Choice |
| --- | --- |
| Backend language | Haskell |
| Backend runtime and infrastructure | IHP |
| HTTP API | Servant |
| Database | PostgreSQL with Hasql / IHP database infrastructure |
| API contract target | OpenAPI 3.1 |
| Web frontend | SvelteKit |
| iOS client | Swift / HealthKit |
| MCP integration | Go adapter |
| FIT ingestion | Haskell FFI → C ABI wrapper → Garmin C++ FIT SDK |
| Development environment | Nix / Nix Flakes |

Use IHP to reduce routine infrastructure work while keeping the Servant API,
domain logic, and PostgreSQL behavior explicit and understandable. Framework
features are available tools, not reasons to expand the current task.

## Authentication runtime

`App.Environment` reads deployment settings and owns the Hasql pool, clock,
password-work semaphore and bounded process-local authentication rate windows.
`Auth.Password` wraps crypton's Argon2id implementation and PHC encoding;
`Auth.Token` generates 256-bit secrets and hashes them for lookup. `Auth.Request`
validates credential transport, cookies, Origin and CSRF. `Auth.Session` resolves
the authenticated principal and coordinates account-locked transactions.
`Api.Auth.Handlers` translates the existing routes into these operations.

Passwords are 15–128 Unicode characters. Usernames are case-sensitive, 3–64 ASCII
letters/digits or `_.-`. Production Argon2id defaults to 64 MiB, three iterations,
one lane; `ARGON_MEMORY_KIB` and `ARGON_ITERATIONS` configure bounded costs. At
most two password calculations run concurrently. Missing-user login performs the
same password verification against a dummy hash. Authentication is limited to 30
requests per minute per direct peer IP and 300 across the process; forwarded IP
headers are not trusted. A reverse proxy must enforce its own client rate limit
when many clients share one backend peer. Multiple backend processes require a
shared limiter before deployment at that scale.

`APP_ORIGIN` must be the exact HTTPS browser origin, without a path or trailing
slash; default `https://localhost:5173`. Use a same-origin HTTPS reverse proxy for
browser development. The server binds to localhost; it does not terminate TLS or
provide cross-origin CORS. `REGISTRATION_OPEN` defaults to `false`; temporarily
enable it for the initial browser registration, then disable it again.
`BROWSER_IDLE_SECONDS`, `BROWSER_ABSOLUTE_SECONDS`, `NATIVE_IDLE_SECONDS` and
`NATIVE_ABSOLUTE_SECONDS` override the contract defaults. Each must be positive,
idle cannot exceed absolute, and absolute cannot exceed one year.

Browser login atomically consumes the old cookie session and creates a new one.
CSRF tokens are reproducible HMACs of the presented cookie, permitting safe token
reuse across browser tabs while persisting only a digest. Login, password change
and account-wide revocation lock the same user row. Password verification occurs
outside transactions; login rechecks the password hash under the lock so a
concurrent password change cannot leave a newly issued session valid.

Session listings use signed cursors scoped to the owner and ordered by creation
time then UUID. The signing key is process-local: after a restart, retry listing
from its first page. Session credentials remain valid across restarts because
their digests and deadlines are durable. Expired/revoked rows are retained for
now; periodic retention cleanup and administrator recovery tooling are subsequent
operational work. No public password-recovery endpoint is implied.

## Manual Workout runtime

`Api.Workout.Handlers` mounts creation, list/detail, user-data replacement and
manual deletion. Both cycling and running reuse the same canonical input types
and sport-specific validation. `Auth.Session.owned` takes the account lock and
rechecks the session before the storage operation, keeping ownership and
revocation checks inside the transaction. It deliberately serializes operations
for one account in this first slice.

`Storage.Workout.Submission` claims `(user_id, submission_id)` using a unique
constraint, hashes the decoded canonical observation/user-data pair, creates the
workout and publishes the mapping in one transaction. Failed validation rolls
back the claim. Matching retries load the current resource; conflicting content
returns `409 submission_conflict`. Deletion clears only the mapped workout ID,
retaining the digest as a tombstone. A matching retry then returns `404` and
cannot recreate the workout. Hash encoding follows storage version 1; changing
it requires a compatibility/migration decision for existing submissions.

`Storage.Workout.Query` reads only the list projection from JSONB. It filters by
owner, exact start boundaries, sport and whole tags, orders by start then UUID,
and fetches at most `limit + 1` rows. A generated NUMERIC calendar key preserves
canonical decimal-second precision for the indexed order, without timestamp
rounding. Signed cursors carry owner/filter scope and the last position. Group
persistence is absent, so no memberships can match a `groupId` filter yet.

Manual deletion uses owner, ID and expected revision in SQL and requires a manual
submission mapping. Unmapped workouts return `409 reconciliation_required`;
source-aware deletion must be implemented alongside import/group persistence.
`deleteEmptyGroups` has no effect while no groups can be stored. Group, import and
export route groups are not mounted. This is an explicit implementation boundary,
not a claim that source suppression or group reconciliation is already available.
