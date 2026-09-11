-- Infrastructure-only identities and retry state. Never imported by Workout.*.
module Import.Types
    ( ImportId (..)
    , ImportOwnerId (..)
    , ImportVersion (..)
    , SourceIdentity (..)
    , ImportKey (..)
    , ImportRecord (..)
    , ImportSuccess (..)
    , ImportAttempt (..)
    , DeviceInfo (..)
    , ImportIntent (..)
    , ImportDecision (..)
    , ImportPartKey (..)
    , ImportedWorkout (..)
    , ImportOutput (..)
    , RefreshCandidate (..)
    , RefreshError (..)
    , ImportKeyError (..)
    , ImportOutputError (..)
    ) where

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import Data.Vector (Vector)
import Workout.Types (WorkoutGroupId, WorkoutId, WorkoutObservation, WorkoutRevision)
import Workout.Validation.Types (UpdateError)

newtype ImportId = ImportId UUID deriving (Eq, Ord, Show)
newtype ImportOwnerId = ImportOwnerId UUID deriving (Eq, Ord, Show)
newtype ImportVersion = ImportVersion Text deriving (Eq, Ord, Show)

-- Identity is owner-scoped. FIT keys refer to actual FIT bytes, not a ZIP or
-- filename. Adapters split containers into logical activities before indexing.
data SourceIdentity
    = FitContentHash Text -- lowercase SHA-256 hex; validated at the boundary
    | HealthKitObject UUID
    | ExternalObject Text Text -- server-validated account namespace and object key
    | ManualSubmission UUID
    | McpSubmission UUID
    deriving (Eq, Ord, Show)

data ImportKey = ImportKey
    { importOwner :: ImportOwnerId
    , importSource :: SourceIdentity
    }
    deriving (Eq, Ord, Show)

-- Persistence must enforce a UNIQUE constraint on ImportKey. These Haskell
-- types cannot prevent concurrent duplicate publications on their own.
data ImportRecord = ImportRecord
    { importId :: ImportId
    , importKey :: ImportKey
    , archivedRawPath :: Maybe FilePath
    , lastSuccessfulImport :: Maybe ImportSuccess
    , lastImportAttempt :: ImportAttempt
    , suppressedAt :: Maybe UTCTime
    , importedDevices :: Vector DeviceInfo
    }
    deriving (Eq, Show)

data ImportSuccess = ImportSuccess
    { successfulOutput :: ImportOutput
    , successfulImportVersion :: ImportVersion
    , importSucceededAt :: UTCTime
    }
    deriving (Eq, Show)

data ImportAttempt
    = ImportPending
    | ImportProcessing UTCTime
    | ImportFailed UTCTime Text
    | ImportSucceeded UTCTime
    deriving (Eq, Show)

data DeviceInfo = DeviceInfo
    { deviceManufacturer :: Maybe Text
    , deviceModel :: Maybe Text
    , deviceSerialNumber :: Maybe Text
    , deviceSoftwareVersion :: Maybe Text
    , deviceRole :: Maybe Text
    , deviceConnection :: Maybe Text
    }
    deriving (Eq, Show)

-- Refresh and retry are explicit; importer upgrades alone do not trigger them.
data ImportIntent = NormalImport | RetryImport | RefreshImport deriving (Eq, Show)
data ImportDecision
    = ReturnExisting ImportOutput
    | BeginImport
    | AwaitCurrentAttempt
    | RequireExplicitRetry
    | InputSuppressed
    deriving (Eq, Show)

-- Opaque, stable identity inside one input. It is not a timestamp or a Sport
-- label (one source can contain several rides). Adapters own its derivation.
newtype ImportPartKey = ImportPartKey Text deriving (Eq, Ord, Show)

data ImportedWorkout = ImportedWorkout
    { importedPartKey :: ImportPartKey
    , importedWorkoutId :: WorkoutId
    }
    deriving (Eq, Show)

-- Single-sport inputs do not create empty or one-member groups. The grouped
-- form requires at least two distinct parts/IDs, checked by validateImportOutput.
data ImportOutput
    = SingleWorkout ImportedWorkout
    | GroupedWorkouts WorkoutGroupId (NonEmpty ImportedWorkout)
    deriving (Eq, Show)

data RefreshCandidate = RefreshCandidate
    { refreshPartKey :: ImportPartKey
    , refreshExpectedRevision :: WorkoutRevision
    , refreshObservation :: WorkoutObservation
    }
    deriving (Eq, Show)

data RefreshError
    = InvalidImportOutput [ImportOutputError]
    | OutputPartsChanged
    | StoredOutputMismatch
    | WorkoutRefreshFailed WorkoutId UpdateError
    deriving (Eq, Show)

-- Stable domain failures; presentation belongs at the eventual API boundary.
data ImportKeyError
    = NilImportOwner
    | NilSourceIdentity
    | InvalidFitContentHash
    | MissingExternalIdentity
    deriving (Eq, Show)

data ImportOutputError
    = DuplicateOutputPartKeys
    | DuplicateOutputWorkoutIds
    | BlankOutputPartKey
    | NilOutputWorkoutId
    | NilOutputGroupId
    | TooFewGroupedWorkouts
    deriving (Eq, Show)
