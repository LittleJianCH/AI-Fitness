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
| Domain | Canonical models, business rules, normalization, and calculations |
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

## Domain: independent business logic

Domain code owns business concepts and operations, including:

- The canonical workout model and activity types.
- Health metrics and data normalization.
- Workout merging.
- Training load and muscle fatigue calculations.
- Recommendation logic.
- Business validation.

These are conceptual areas to introduce as needed, not modules to scaffold
up front. Core logic must be testable without constructing an HTTP request.
It must not know whether an operation originated from the web UI, iOS, or MCP.

The intended operation flow is:

```text
Servant handler
      ↓
Domain operation
      ↓
Infrastructure / database query or transaction
      ↓
PostgreSQL
```

HTTP parsing, response construction, and framework controller concerns belong
outside domain logic. Keep pure calculations and validation separate from
database effects where practical; add abstractions only to solve a present need.

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

The planned client authentication mechanisms are:

| Client | Mechanism | Storage and separation |
| --- | --- | --- |
| SvelteKit web UI | IHP session cookie | Use `HttpOnly`, `Secure`, and an appropriate `SameSite` policy |
| iOS | `Authorization: Bearer <token>` | Store the client token in Keychain |
| Go MCP adapter | `Authorization: Bearer <token>` | Use a token independent of the iOS token |

Store only token hashes in the database for bearer-token authentication.
Keep credential handling at the infrastructure and API boundaries.

Do not introduce JWT, OAuth/OIDC, refresh tokens, or RBAC unless a concrete
requirement calls for them. These authentication choices describe the intended
design; they do not require implementing all client authentication in the first
development stage.

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

Do not design FIT ingestion around spawning a separate parser CLI or subprocess.
Introduce the FFI integration when FIT ingestion becomes an active requirement.

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
├── Domain/
│   ├── Workout/
│   ├── TrainingLoad/
│   └── MuscleFatigue/
├── Infrastructure/
│   ├── Database/
│   ├── Auth/
│   ├── Storage/
│   └── Fit/
└── Application/
```

This is not a required directory layout. Clear responsibilities and dependencies
matter more than directory count. Create modules as concrete features need them.

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
