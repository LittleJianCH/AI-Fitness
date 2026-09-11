# Nix, Dependencies, and Build Verification

**Read when:** changing dependencies, shared environments, toolchain settings, build scripts, or CI setup.

Keep one root `flake.nix` and `flake.lock`. Respect the existing separation between IHP's Haskell package set and the stable general-tool package set. Do not force all transitive `nixpkgs` inputs to follow one version merely to shorten the lockfile. Do not run broad dependency updates during unrelated changes. [repo-flake] [nix-flake]

Nix owns shared environment/toolchain selection; ecosystem tooling still owns its dependency/build model:

| Component | Dependency/build inputs |
| --- | --- |
| Haskell backend | IHP package set and `ghc.withPackages`, synchronized with `backend/App.cabal`; Make targets define project checks/builds. |
| Web | Nix-provided Node/pnpm environment plus `web/package.json` and `web/pnpm-lock.yaml`. |
| API contract consumers | Repository generator configuration and locks under `contracts/`; derived outputs remain ignored. |
| MCP | Pinned Go toolchain, `go.mod`, and `go.sum` when initialized. |
| iOS | Explicit Xcode/SDK/Swift settings and SPM resolution where used. Xcode installation, signing, simulator/device execution remain platform-managed. |
| Android | Nix-selected compatible host tooling where practical, Gradle Wrapper/build files, declared SDK levels, and dependency locking when initialized. |
| FIT adapter | Pinned Garmin SDK input, compiler/build configuration, and project-owned native adapter sources. |

Do not create a competing global dependency workflow through ad hoc `brew`, `npm -g`, `go install @latest`, GHCup, or another version manager when the dependency belongs in the shared environment. Do not put secrets in Nix expressions or derivation outputs. Keep local untracked environment data outside reproducible store inputs.

A development shell is not proof of a hermetic release build. Use the repository's executable configuration and README to determine what checks actually exist; do not copy an old command list forward merely because it appeared in this guide. `nix flake check` must not be reported as application verification unless the flake actually defines the relevant checks. [repo-readme] [repo-makefile] [nix-check]

Current backend targets include build, domain/API checking, tests, formatting/linting, contract generation/tests, and FIT/native checks. The web app defines `check`, `lint`, `test`, `test:e2e`, and `build`, together with explicit demo run/build/preview scripts. See `web/README.md` for generation prerequisites and browser-test setup. Contract generation and TypeScript/Swift consumer checks are documented in `README.md` and `docs/api-contract.md`. Run the smallest relevant configured checks for the changed boundary and report platform-specific checks separately.

When this document and executable manifests disagree, the manifests/targets are authoritative for what can be run; update this guide if the disagreement reflects a durable stack change.

[nix-check]: references.md#nix-check
[nix-flake]: references.md#nix-flake
[repo-flake]: references.md#repo-flake
[repo-makefile]: references.md#repo-makefile
[repo-readme]: references.md#repo-readme
