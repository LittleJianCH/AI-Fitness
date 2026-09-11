module Import.State (planImport, recordFailure, validateImportKey) where

import Data.Char (isDigit)
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import qualified Data.UUID.Types as UUID
import Import.Types

-- This is a planning decision, not an atomic claim. The persistence layer owns
-- unique constraints, transactions, authorization and recovery of stale attempts.
planImport :: ImportIntent -> ImportRecord -> ImportDecision
planImport intent record
    | isJust (suppressedAt record) = InputSuppressed
    | ImportProcessing _ <- lastImportAttempt record = AwaitCurrentAttempt
    | intent == NormalImport
    , Just success <- lastSuccessfulImport record =
        ReturnExisting (successfulOutput success)
    | intent == NormalImport, ImportFailed _ _ <- lastImportAttempt record = RequireExplicitRetry
    | otherwise = BeginImport

-- Failure only changes the latest attempt. Prior mapping and successful version
-- remain usable, even when a historical refresh fails.
recordFailure :: UTCTime -> Text -> ImportRecord -> ImportRecord
recordFailure now reason record = record {lastImportAttempt = ImportFailed now reason}

validateImportKey :: ImportKey -> [ImportKeyError]
validateImportKey key = [NilImportOwner | owner == UUID.nil] ++ source
  where
    ImportOwnerId owner = importOwner key
    nonNil x = [NilSourceIdentity | x == UUID.nil]
    nonBlank x = not (T.null (T.strip x))
    source = case importSource key of
        FitContentHash hash ->
            [ InvalidFitContentHash
            | T.length hash /= 64 || not (T.all (\c -> isDigit c || c `elem` ['a' .. 'f']) hash)
            ]
        HealthKitObject x -> nonNil x
        ExternalObject account object -> [MissingExternalIdentity | not (nonBlank account && nonBlank object)]
        ManualSubmission x -> nonNil x
        McpSubmission x -> nonNil x
