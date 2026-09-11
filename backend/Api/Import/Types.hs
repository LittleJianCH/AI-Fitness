{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Api.Import.Types
    ( ImportRecord (..)
    , Source (..)
    , FitSource (..)
    , HealthKitSource (..)
    , ImportStatus (..)
    , ImportOutput (..)
    , ImportedPart (..)
    , Failure (..)
    , ArchiveState (..)
    , ImportIntent (..)
    , RefreshImport (..)
    , ExpectedWorkout (..)
    , HealthKitSubmission (..)
    , ImportPart (..)
    ) where

import Api.Codec (ViaJSON (..))
import Api.Common.Types
import Api.Workout.Codec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.List.NonEmpty (NonEmpty)
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import GHC.Generics (Generic)
import Workout.Types
    ( WorkoutGroupId
    , WorkoutId
    , WorkoutObservation
    , WorkoutRevision
    , WorkoutUserData
    )

data Source = Fit FitSource | HealthKit HealthKitSource
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON Source)

newtype FitSource = FitSource {_sha256 :: Text}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON FitSource)

newtype HealthKitSource = HealthKitSource {_objectId :: Id "HealthKitObject"}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON HealthKitSource)

data ArchiveState = Retained | Removed | NotApplicable
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON ArchiveState)

data ImportStatus = Pending | Processing | Failed | Succeeded | Suppressed
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON ImportStatus)

data ImportRecord = ImportRecord
    { _id :: Id "Import"
    , _revision :: Revision
    , _source :: Source
    , _status :: ImportStatus
    , _archive :: ArchiveState
    , _createdAt :: Timestamp
    , _updatedAt :: Timestamp
    , _lastSuccess :: Maybe ImportOutput
    , _failure :: Maybe Failure
    }
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON ImportRecord)

data ImportOutput = ImportOutput
    { _parts :: NonEmpty ImportedPart
    , _groupId :: Maybe WorkoutGroupId
    , _parserVersion :: Text
    , _importedAt :: Timestamp
    }
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON ImportOutput)

data ImportedPart = ImportedPart {_partKey :: Text, _workoutId :: WorkoutId}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON ImportedPart)

data Failure = Failure {_code :: Text, _message :: Text, _retryable :: Bool}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON Failure)

data ImportIntent = Normal | Retry | Refresh
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON ImportIntent)

data ExpectedWorkout = ExpectedWorkout {_id :: WorkoutId, _revision :: WorkoutRevision}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON ExpectedWorkout)

data RefreshImport = RefreshImport {_expectedRevision :: Revision, _workouts :: NonEmpty ExpectedWorkout}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON RefreshImport)

data HealthKitSubmission = HealthKitSubmission
    { _objectId :: Id "HealthKitObject"
    , _intent :: ImportIntent
    , _expectedRevision :: Maybe Revision
    , _expectedWorkouts :: [ExpectedWorkout]
    , _parts :: NonEmpty ImportPart
    }
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON HealthKitSubmission)

data ImportPart = ImportPart
    {_partKey :: Text, _observation :: WorkoutObservation, _initialUserData :: WorkoutUserData}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON ImportPart)
