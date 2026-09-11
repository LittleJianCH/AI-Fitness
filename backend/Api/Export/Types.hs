{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Api.Export.Types (CanonicalExport (..), CanonicalVersion (..), ExportReceipt (..), Platform (..), RecordExport (..)) where

import Api.Codec (ViaEnum (..), ViaJSON (..))
import Api.Common.Types
import Api.Workout.Codec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import GHC.Generics (Generic)
import Workout.Types (Workout, WorkoutGroup, WorkoutId, WorkoutRevision)

data CanonicalVersion = CanonicalV1
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaEnum CanonicalVersion)

data CanonicalExport = CanonicalExport
    { _version :: CanonicalVersion
    , _exportedAt :: Timestamp
    , _workouts :: [Workout]
    , _groups :: [WorkoutGroup]
    }
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON CanonicalExport)

data Platform = AppleHealth
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaEnum Platform)

data ExportReceipt = ExportReceipt
    { _id :: Id "ExportReceipt"
    , _workoutId :: WorkoutId
    , _workoutRevision :: WorkoutRevision
    , _platform :: Platform
    , _externalId :: Text
    , _exportedAt :: Timestamp
    }
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON ExportReceipt)

data RecordExport = RecordExport {_workoutRevision :: WorkoutRevision, _platform :: Platform, _externalId :: Text}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON RecordExport)
