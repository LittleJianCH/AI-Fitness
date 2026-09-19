{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Api.Workout.Types
    ( Workout (..)
    , WorkoutObservation (..)
    , WorkoutUserData (..)
    , SportFilter (..)
    , SportSummary (..)
    , WorkoutCard (..)
    , ManualWorkout (..)
    , EditWorkout (..)
    , PowerCurve (..)
    , WorkoutAnalysis (..)
    ) where

import Api.Codec (ViaJSON (..))
import Api.Common.Types (Id)
import Api.Workout.AnalysisCodec ()
import Api.Workout.Codec ()
import Api.Workout.PowerCurveCodec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToParamSchema, ToSchema)
import GHC.Generics (Generic)
import Web.HttpApiData (FromHttpApiData)
import Workout.Analysis.Types (WorkoutAnalysis (..))
import qualified Workout.Cycling.Types as C
import Workout.PowerCurve.Types (PowerCurve (..))
import qualified Workout.Running.Types as R
import Workout.Types
    ( Summaries
    , TimeRange
    , Workout (..)
    , WorkoutId
    , WorkoutObservation (..)
    , WorkoutRevision
    , WorkoutUserData (..)
    )

data SportFilter = Cycling | Running
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema, ToParamSchema, FromHttpApiData) via (ViaJSON SportFilter)

data SportSummary
    = CyclingSummary (Summaries C.CyclingSummary)
    | RunningSummary (Summaries R.RunningSummary)
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON SportSummary)

data WorkoutCard = WorkoutCard
    { _id :: WorkoutId
    , _revision :: WorkoutRevision
    , _range :: TimeRange
    , _userData :: WorkoutUserData
    , _summary :: SportSummary
    }
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON WorkoutCard)

data ManualWorkout = ManualWorkout
    { _submissionId :: Id "Submission"
    , _observation :: WorkoutObservation
    , _userData :: WorkoutUserData
    }
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON ManualWorkout)

data EditWorkout = EditWorkout
    {_expectedRevision :: WorkoutRevision, _userData :: WorkoutUserData}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON EditWorkout)
