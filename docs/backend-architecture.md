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

The current implementation is deliberately small: IHP supplies configuration and
request logging, Servant serves `GET /api/v1/hello` as plain text (`hello world`),
and Warp runs the application on localhost. The backend does not initialize a
database, create a connection pool, generate schema types, or start PostgreSQL.
The MVC welcome page, sessions, development UI, and background workers are not
part of this entry point. Database integration, domain operations, authentication,
OpenAPI generation, and clients below describe future work.

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
infrastructure, sessions, and required WAI middleware around this flow.
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
- Web sessions.
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
target contract version; generator compatibility and any conversion needed
must be verified when implementing that pipeline. This document does not
assume that the installed libraries already provide it.

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
by the hello endpoint. The standalone test runner covers canonical validation,
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

PostgreSQL is the primary persistent database. Use the Hasql-based
infrastructure supplied by the selected IHP version.

Database design must explicitly use primary keys, foreign keys, unique
constraints, check constraints, indexes, and transactions as appropriate.
Haskell types alone do not guarantee the integrity of stored data.

For operations that perform multiple related changes, make the transaction
boundary explicit. Important invariants belong in database constraints as well
as application validation. PostgreSQL is the final enforcement layer for stored
data integrity.

## Authentication

Web username/password registration and login are required. The authentication,
session and token architecture remains to be redesigned; the previous
web-session/iOS-token/MCP-token table is superseded and is not an implementation
requirement. Authentication is not implemented by the current hello API or pure
workout model. Keep credential handling and server-side authorization at the
appropriate application and API boundaries when that work begins.

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
