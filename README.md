# AI Fitness

A personal fitness and training data system managed as a monorepo.
The current backend is a minimal Servant API using IHP configuration and logging.
The SvelteKit frontend has not been initialized.

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
