# Haskell: Readable Functional Code

**Read when:** editing Haskell implementation or reviewing Haskell-specific behavior.

## Pure core and honest effect boundaries

Domain calculations and validation SHOULD be ordinary pure functions. Reading files, invoking the FIT SDK, accessing the database, obtaining time/randomness, and performing network operations belong to explicit effectful boundaries. Pass time/configuration into calculations instead of reading global state from inside them.

Prefer idiomatic Functor, Applicative, and Monad operators when they make transformations, sequencing, and dependencies clear. Readability is judged for an experienced Haskell reader. Choose notation by the structure of the computation, without expanding familiar operator expressions solely for explicitness.

Use applicative composition for computations whose inputs do not depend on earlier results, and monadic composition for dependent steps. Use `do` notation when named intermediate results, branching, or longer sequences make it clearer. Preserve effects, sequencing, and failure behavior when changing notation.

Point-free composition, traversal, folds, pattern matching, guards, and comprehensions are welcome where they reveal the data flow. Introduce names or explicit arguments when precedence, nesting, or changes in operator direction obscure it. Favor familiar idioms and clarity over operator density or unnecessary custom operators.

Do not introduce `State` for a simple `a -> a` transformation. Conversely, do not prohibit `ST`, local mutable vectors, or explicit recursion when a measured algorithm or a recursive structure calls for them. Do not add lens machinery for a small record update or an effect stack for a pure helper.

## Types and totality

Export the smallest useful module API. Give top-level functions signatures. Hide constructors for validated values when callers could otherwise violate their invariant. Use qualified imports for ambiguous library names and avoid bringing HTTP/database context into pure modules.

Prefer `Text` for application text and `ByteString` for binary input. Prefer `Maybe`, `Either`, and `NonEmpty` where their meaning matches the requirement. Avoid unchecked `head`, `fromJust`, `read`, indexing, `error`, and `undefined` on externally influenced paths. A smart constructor is ineffective if a derived decoder or another exported constructor bypasses its checks.

Illustrative complete module; this is a style example, not a finalized workout model:

```haskell
module Domain.Distance
    ( DistanceMeters
    , DistanceError (..)
    , mkDistanceMeters
    , distanceMeters
    ) where

newtype DistanceMeters = DistanceMeters Double
    deriving (Eq, Show)

data DistanceError
    = NonFiniteDistance
    | NegativeDistance
    deriving (Eq, Show)

mkDistanceMeters :: Double -> Either DistanceError DistanceMeters
mkDistanceMeters value
    | isNaN value || isInfinite value = Left NonFiniteDistance
    | value < 0 = Left NegativeDistance
    | otherwise = Right (DistanceMeters value)

distanceMeters :: DistanceMeters -> Double
distanceMeters (DistanceMeters value) = value
```

A derived `FromJSON` instance must not become a second unchecked entry point for such a validated type. Decode an input DTO and validate it, or implement decoding through the constructor.

## Composition and failures

`traverse validate xs` expresses validation over a collection without hand-written sequencing. `Either` ordinarily stops at the first failure. Applicative syntax alone does not accumulate errors or run work concurrently; use the selected type's actual semantics. Adopt error accumulation only when the user experience needs it.

Expected domain failures SHOULD have domain-specific error types, not HTTP status codes or arbitrary strings. Map them to transport errors at the boundary. An `IO (Either e a)` signature does not automatically convert every exception into `Left`: explicitly handle intended operational failures, preserve asynchronous cancellation, and use `bracket`/appropriate resource combinators for cleanup.

If `effectful` is introduced, limit it to operations that need capabilities such as storage or external services. Keep interpreters at integration boundaries. Do not create one effect per helper or propagate an enormous catch-all effect constraint into every module.

## Strictness, extensions, and tools

Use straightforward aggregation first. For large streams, review retention and strictness; `foldl'` forces an accumulator only to weak head normal form, so a lazy tuple can still retain work. Choose streaming or stricter fields with representative measurements, not blanket `Strict`/`StrictData` changes.

Keep extensions deliberate and compatible with the pinned compiler. The current `Haskell2010` baseline does not authorize using record-dot syntax or other extensions without declaring them. Keep current warning enforcement; use one adopted formatter, with Fourmolu as a suggested choice. Treat HLint suggestions as review input, not an instruction to make readable code point-free. [repo-cabal] [repo-makefile] [ghc-warnings]

The `Domain.Distance` example is preserved from the source guide and was not compiled as part of this documentation-only split. Verify it against the repository's toolchain before adopting it.

[ghc-warnings]: references.md#ghc-warnings
[repo-cabal]: references.md#repo-cabal
[repo-makefile]: references.md#repo-makefile
