# Haskell: Readable Functional Code

**Read when:** editing Haskell implementation or reviewing Haskell-specific behavior.

## Pure core and honest effect boundaries

Domain calculations and validation SHOULD be ordinary pure functions. Reading files, invoking the FIT SDK, accessing the database, obtaining time/randomness, and performing network operations belong to explicit effectful boundaries. Pass time/configuration into calculations instead of reading global state from inside them.

Prefer idiomatic Functor, Applicative, and Monad operators when they make transformations, sequencing, and dependencies clear. Readability is judged for an experienced Haskell reader. Choose notation by the structure of the computation rather than maximizing either explicit variables or operator density.

Use applicative composition for computations whose inputs do not depend on earlier results, and monadic composition for dependent steps. Use `do` notation when named intermediate results, branching, or longer sequences make it clearer. Point-free composition, traversal, folds, pattern matching, guards, and comprehensions are welcome where they reveal data flow; introduce names when precedence or nesting obscures it.

Do not introduce `State` for a simple `a -> a` transformation. Conversely, do not prohibit `ST`, local mutable vectors, or explicit recursion when a measured algorithm or recursive structure calls for them. Do not add lens machinery for a small record update or an effect stack for a pure helper.

## Types and totality

Export the smallest useful module API and give top-level functions signatures. Hide constructors for validated values when callers could otherwise violate their invariant; when constructors are intentionally public candidate values, ensure publication/write paths run the canonical validator. Avoid bringing HTTP/database context into pure modules.

Prefer `Text` for application text and `ByteString` for binary input. Prefer `Maybe`, `Either`, and `NonEmpty` where their meaning matches the requirement. Avoid unchecked `head`, `fromJust`, `read`, indexing, `error`, and `undefined` on externally influenced paths. A derived decoder must not become an unchecked path around a validated constructor or publication boundary.

## Composition and failures

Use `traverse`, folds, and standard combinators when they express the operation more directly than hand-written recursion. `Either` ordinarily stops at the first failure; applicative syntax alone does not accumulate errors or run work concurrently. Adopt error accumulation only when the product behavior needs it.

Expected domain failures SHOULD have domain-specific error types, not HTTP status codes or arbitrary strings. Map them to transport errors at the boundary. An `IO (Either e a)` signature does not automatically convert every exception into `Left`: explicitly handle intended operational failures, preserve asynchronous cancellation, and use `bracket` or equivalent resource combinators for cleanup.

If `effectful` is introduced, limit it to operations that need capabilities such as storage or external services. Keep interpreters at integration boundaries. Do not create one effect per helper or propagate an enormous catch-all effect constraint into every module.

## Strictness, extensions, and tools

Use straightforward aggregation first. For large streams, review retention and strictness with representative data; choose streaming or stricter fields because measurements justify them, not by defaulting the whole project to strict evaluation.

Keep extensions deliberate and compatible with the pinned compiler. The current language baseline and enabled extensions are defined by executable configuration, not newer examples on the web. Fourmolu is the adopted formatter and HLint is review input rather than an instruction to make code point-free. Use the current Make targets for formatting/linting and relevant checks instead of duplicating a command matrix here. [repo-cabal] [repo-makefile] [ghc-warnings]

[ghc-warnings]: references.md#ghc-warnings
[repo-cabal]: references.md#repo-cabal
[repo-makefile]: references.md#repo-makefile
