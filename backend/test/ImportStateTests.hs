{-# LANGUAGE OverloadedStrings #-}

module ImportStateTests (cases) where

import qualified Data.Text as T
import qualified Data.UUID.Types as UUID
import Fixtures
import Import.State
import Import.Types

cases :: [(String, Bool)]
cases =
    [
        ( "same successful FIT returns existing result"
        , planImport NormalImport importRecord == ReturnExisting singleOutput
        )
    ,
        ( "failed refresh preserves success mapping and version"
        , lastSuccessfulImport failed == lastSuccessfulImport importRecord
        )
    ,
        ( "failed refresh still serves existing result"
        , planImport NormalImport failed == ReturnExisting singleOutput
        )
    ,
        ( "first failure needs explicit retry"
        , planImport NormalImport (failed {lastSuccessfulImport = Nothing}) == RequireExplicitRetry
        )
    ,
        ( "explicit retry is allowed"
        , planImport RetryImport (failed {lastSuccessfulImport = Nothing}) == BeginImport
        )
    ,
        ( "processing input is not published twice"
        , planImport NormalImport importRecord {lastImportAttempt = ImportProcessing start}
            == AwaitCurrentAttempt
        )
    ,
        ( "suppressed input stays suppressed"
        , planImport RefreshImport importRecord {suppressedAt = Just start} == InputSuppressed
        )
    ,
        ( "explicit HealthKit refresh does not skip an existing UUID"
        , planImport
            RefreshImport
            importRecord {importKey = ImportKey owner (HealthKitObject (UUID.fromWords 0 0 0 6))}
            == BeginImport
        )
    ,
        ( "source identities do not use time overlap"
        , importKey importRecord /= ImportKey owner (HealthKitObject (UUID.fromWords 0 0 0 6))
        )
    , ("valid content identity", null (validateImportKey (importKey importRecord)))
    ,
        ( "filename is not a FIT content identity"
        , not (null (validateImportKey (ImportKey owner (FitContentHash "renamed.fit"))))
        )
    ,
        ( "identity failures accumulate in owner then source order"
        , validateImportKey (ImportKey (ImportOwnerId UUID.nil) (HealthKitObject UUID.nil))
            == [NilImportOwner, NilSourceIdentity]
        )
    ,
        ( "malformed FIT identity has a typed error"
        , validateImportKey (ImportKey owner (FitContentHash "renamed.fit")) == [InvalidFitContentHash]
        )
    ,
        ( "suppression takes precedence over an active attempt"
        , planImport
            RefreshImport
            importRecord {suppressedAt = Just start, lastImportAttempt = ImportProcessing start}
            == InputSuppressed
        )
    ,
        ( "non-ASCII digits cannot form a FIT content hash"
        , validateImportKey (ImportKey owner (FitContentHash (T.replicate 64 "０"))) == [InvalidFitContentHash]
        )
    ]
  where
    failed = recordFailure (at 1) "decoder failed" importRecord
    owner = importOwner (importKey importRecord)
