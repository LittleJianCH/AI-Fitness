{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Api.WorkoutGroup.Types (GroupView (..), GroupData (..), CreateGroup (..), EditGroup (..)) where

import Api.Codec (ViaJSON (..))
import Api.Common.Types
import Api.Workout.Codec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.List.NonEmpty (NonEmpty)
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import GHC.Generics (Generic)
import Workout.Types (WorkoutGroup, WorkoutId)

data GroupView = GroupView {_revision :: Revision, _group :: WorkoutGroup}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON GroupView)

data GroupData = GroupData {_title :: Text, _notes :: Maybe Text, _members :: NonEmpty WorkoutId}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON GroupData)

data CreateGroup = CreateGroup {_submissionId :: Id "Submission", _data :: GroupData}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON CreateGroup)

data EditGroup = EditGroup {_expectedRevision :: Revision, _data :: GroupData}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON EditGroup)
