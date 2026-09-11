# Nix, Dependencies, and Build Verification

**Read when:** changing dependencies, shared environments, toolchain settings, build scripts, or CI setup.

Keep one root `flake.nix` and `flake.lock`. Respect the existing separation between IHP's Haskell package set and the stable general-tool package set. Do not force all transitive `nixpkgs` inputs to follow one version merely to shorten the lockfile. Do not run broad dependency updates during unrelated changes. [repo-flake] [nix-flake]

Nix owns the shared environment/toolchain selection; ecosystem tooling retains responsibility for its dependency/build model:

| Component | Dependency/build inputs |
| --- | --- |
| Current Haskell skeleton | IHP package set and `ghc.withPackages`, synchronized with `backend/App.cabal`; current Makefile builds against that environment. |
| Web | Pinned Node/pnpm environment, `package.json`, and `pnpm-lock.yaml` when initialized. |
| MCP | Pinned Go toolchain, `go.mod`, and `go.sum` when initialized. |
| iOS | Explicit Xcode/SDK/Swift settings and SPM resolution where used. Xcode installation, signing, and simulator/device execution remain platform-managed. |
| Android | Nix-selected compatible host tooling where practical, Gradle Wrapper/build files, declared SDK levels, and dependency locking where configured. |
| FIT adapter | Pinned SDK input, compiler/build configuration, and the approved source-fetch procedure. |

Do not create a competing global dependency workflow through ad hoc `brew`, `npm -g`, `go install @latest`, GHCup, or another version manager when the dependency belongs in the shared environment. Do not put secrets in Nix expressions or derivation outputs. Keep local untracked environment data outside reproducible store inputs.

A development shell is not proof of a hermetic release build. The current flake defines development shells, not application build/test `checks`. Therefore, `nix flake check` alone must not be reported as a successful backend compilation/test run. Add actual checks incrementally when that is the requested task. [repo-flake] [nix-check]

Current documented checks to run from the repository root, not checks performed while preparing this guide:

```sh
nix develop -c make -C backend
nix develop -c hlint backend
```

Before running a command from older documentation, verify the executable and project script/target exist. Future frontend, mobile, MCP, generation, and database checks need to be configured before being claimed. Report skipped platform-specific checks separately; a Linux check is not an iOS build.

[nix-check]: references.md#nix-check
[nix-flake]: references.md#nix-flake
[repo-flake]: references.md#repo-flake
