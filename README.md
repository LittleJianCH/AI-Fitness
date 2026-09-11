# AI Fitness

A personal fitness and training data system managed as a monorepo.
The current backend is a minimal Servant API using IHP configuration and logging.
The `web/` directory contains a minimal Svelte 5 / SvelteKit frontend with strict TypeScript.
Canonical workout/import models and a generated API contract are available;
product endpoints are not mounted yet.

## Run the backend

With Nix installed and `nix-command` and `flakes` enabled:

```sh
./scripts/backend_dev
make run
```

The script enters the Nix environment in `backend/`. `make run` compiles and starts
only the API. In another terminal:

```sh
curl http://127.0.0.1:8000/api/v1/hello
# hello world
```

Use `PORT=8080 make run` to change the port. Ctrl-C stops the server; `exit` leaves
the development shell. No database, SQL initialization, or background services
are started. `make` compiles without starting the server.

## Run the web app

```sh
./scripts/web_dev
pnpm install --frozen-lockfile
pnpm dev
```

Open http://localhost:5173. The initial page is a standalone placeholder and does
not call the backend. Ctrl-C stops the server; `exit` leaves the development shell.
See [Web development](web/README.md) for checks and project structure.
See [Web UI Design](docs/web-design.md) for visual style, responsive layouts and
interaction design.

## Domain checks

Inside the development shell in `backend/`:

```sh
make check test format-check lint
```

This checks all workout/import modules and runs pure validation and update
scenarios. FIT integration has separate checks below. Persistence and platform sync
are not implemented. `make` continues to build the existing hello API.

`make format` applies Fourmolu to backend sources and tests using the root
`fourmolu.yaml`. The formatter and HLint are provided by the pinned Nix environment;
`format-check` checks without editing. Tests are separated by workout validation,
import-state decisions and import-output refresh behavior.

## API contract

The [API contract guide](docs/api-contract.md) defines authentication, workouts,
groups, imports and exports for web/iOS development. Servant definitions reuse
the canonical model and generate OpenAPI 3.1, TypeScript and Swift clients.
Feature handlers, authentication and persistence are subsequent work.

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
