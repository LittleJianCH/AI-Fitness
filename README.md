# AI Fitness

A personal fitness and training data system managed as a monorepo.
The backend uses Servant, IHP configuration, Hasql and PostgreSQL.
The `web/` directory contains a Svelte 5 / SvelteKit training-review demo with strict TypeScript.
Canonical workout/import models and a generated API contract are available;
authentication and manual Workout endpoints now use PostgreSQL.

## Run the iOS app

The `ios/` directory contains SwiftUI login, workout browsing and explicit Apple Health import
and its shared Swift API/session core. See [iOS development](ios/README.md) for contract generation,
Xcode setup, backend connection, and isolated simulator integration tests.

## Run the backend

With Nix installed and `nix-command` and `flakes` enabled:

```sh
./scripts/backend_dev
export DATABASE_URL='host=localhost dbname=ai_fitness user=ai_fitness'
make migrate
make run
```

The script enters the Nix environment in `backend/`. `make run` compiles and starts
only the API; PostgreSQL and its database/role must already exist. In another terminal:

```sh
curl http://127.0.0.1:8000/api/v1/hello
# hello world
```

Use `PORT=8080 make run` to change the port. Ctrl-C stops the server; `exit` leaves
the development shell. No database process or background services are started. The server opens a
connection pool and checks connectivity; migrations are a separate explicit step. `make` compiles without starting the server.

## Run the web demo

```sh
./scripts/web_generate
./scripts/web_dev
pnpm install --frozen-lockfile
pnpm demo
```

Open http://127.0.0.1:5173/workouts. The demo uses generated API contracts with
synthetic read-only responses. Backend authentication and manual Workout handlers
are implemented; the web demo is not connected to them yet. See [Web development](web/README.md) for data flow, checks and
ordinary-mode behavior, and [Web UI Design](docs/web-design.md) for design rules.
Ctrl-C stops the server; `exit` leaves the development shell.

## Domain checks

Inside the development shell in `backend/`:

```sh
make check test format-check lint
```

This checks all workout/import modules and runs pure validation and update
scenarios. FIT and PostgreSQL integration have separate checks below. Platform sync
is not implemented. `make` builds the API server, including authentication.

`make format` applies Fourmolu to backend sources and tests using the root
`fourmolu.yaml`. The formatter and HLint are provided by the pinned Nix environment;
`format-check` checks without editing. Tests are separated by workout validation,
import-state decisions and import-output refresh behavior.

## API contract

The [API contract guide](docs/api-contract.md) defines authentication, workouts,
groups, imports and exports for web/iOS development. Servant definitions reuse
the canonical model and generate OpenAPI 3.1, TypeScript and Swift clients.
Authentication, user/session storage and manual Workout CRUD are implemented.
HealthKit submission/detail handlers support single-part cycling/running imports
with durable retry identity and explicit refresh. Group, other import, and export
handlers are added separately. See the guide for the exact mounted routes.

From the root inside `nix develop`:

```sh
make -C backend contract contract-test
cd contracts
npm ci --ignore-scripts
npm run generate
npm run check
```

The guide also includes the macOS Swift check. Generated outputs are ignored;
generator configuration and dependency locks are maintained in `contracts/`.

## PostgreSQL storage

The backend has user, session and canonical Workout storage operations. Authentication uses
the same storage through a pool in the running HTTP server. PostgreSQL and IHP's migration executable are in
the default Nix shell. Apply migrations to an explicitly configured database:

```sh
export DATABASE_URL='host=localhost dbname=ai_fitness user=ai_fitness'
make -C backend migrate
```

The database and its role must already exist. Supply credentials using the local
PostgreSQL authentication setup; do not put secrets in source files. Run one
migration process at a time. SQL files in `backend/Application/Migration/` are the
authoritative history; IHP records applied revisions in `schema_migrations`.

Run isolated integration tests from the repository root inside `nix develop`:

```sh
make -C backend storage-test http-test
```

This creates a private temporary PostgreSQL cluster with no TCP listener, tests
migrations, rollback, ownership and concurrent updates, then restarts PostgreSQL
to verify durability. It never uses an existing `DATABASE_URL` and removes its
temporary cluster afterwards. See [storage boundaries](docs/backend-architecture.md#database-and-integrity)
for the schema, transaction interface and implementation limits.

## Local FIT parsing

`Import.Fit.readFit` reads a local file; `parseFit` accepts a strict
`ByteString`. Both return `IO (Either FitError WorkoutObservation)`. The decoder
calls Garmin's C++ SDK in process through a small C ABI, then Haskell normalizes
and validates the observation. No upload endpoint or database writes are added.

The initial subset accepts one complete activity file with exactly one cycling
or running session. It reads absolute start/end times, reported elapsed/timer time and total
distance, plus heart-rate, power, speed, distance, cadence, altitude and GPS samples. Missing values stay
absent and zero power stays zero. Enhanced speed takes precedence when valid.
Other sports, multiple sessions and non-activity files return `UnsupportedFit`.
Laps, course points, events, device metadata, other summaries and extensions
are not mapped yet; do not use this subset as a full-fidelity import or export.

Cadence uses `cadence256` when valid, otherwise integer cadence plus its optional
fraction. Cycling retains cycles/minute; running multiplies by two for total
steps/minute. GPS requires both coordinates and converts FIT semicircles to WGS84
degrees once. Negative altitude is valid. No sensor gaps are filled.

In the Nix development shell, from `backend/`:

```sh
make fit-test native-format-check native-sanitize
```

Tests generate deterministic synthetic FIT bytes using the SDK encoder under
ignored `backend/build/`. No FIT binary fixtures are committed. Tests cover unit
and UTC conversion, missing/invalid values, zero values, enhanced speed, distinct
durations, malformed/truncated/CRC failures, unsupported types, timestamp
validation, limits and repeated allocation/free. `native-sanitize` instruments
our C ABI adapter with ASan/UBSan; the pinned SDK library is not instrumented.

Private sample checks are optional and print only success or a bounded error
category. Keep real files **outside every worktree**; never commit source files,
extracted records, private filenames or snapshots. For example, with shell
variables pointing to files in a private directory outside the repository:

```sh
./build/fit-tests --private-cycling "$FIT_CYCLING_SAMPLE"
./build/fit-tests --private-running "$FIT_RUNNING_SAMPLE"
```

Both private checks require successful decoding and the expected sport. `.gitignore` excludes FIT files as an additional
precaution, not as permission to place private inputs in the source tree.

Inputs are limited to 16 MiB, 100,000 record messages and 250,000 total messages.
The native call uses `safe` FFI; other Haskell threads can run, but cancellation
waits for native decoding to return. These limits are not a hard wall-clock
timeout or a proof of SDK memory safety. Native memory is copied into Haskell
values and released with `bracket`, including on Haskell exceptions.

## Dependencies and architecture

The root `flake.nix` and `flake.lock` manage the development environment:

- Haskell tools and libraries use IHP's pinned Nixpkgs with the IHP overlay.
- General tools use Nixpkgs 26.05 stable.
- Upstream transitive dependencies keep their existing pins.

Declare Haskell libraries in `haskell.ghc.withPackages` and keep the dependency
list in `backend/App.cabal` consistent. The Makefile builds against the packages
provided by Nix, without a separate Cabal dependency download.

See [Backend architecture](docs/backend-architecture.md) for the current design
and future boundaries. Update affected documentation when implementation or
architecture changes. All repository documentation is written in English.

Authentication deployment settings, HTTPS browser setup, credential handling and
current operational limits are documented in the
[authentication runtime](docs/backend-architecture.md#authentication-runtime).
`http-test` uses a fresh private database and synthetic credentials; it never uses
your configured development database.
