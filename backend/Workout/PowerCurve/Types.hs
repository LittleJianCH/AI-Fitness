{-# LANGUAGE DeriveGeneric #-}

module Workout.PowerCurve.Types (PowerCurve (..), PowerCurvePoint (..), PowerEffort (..)) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Vector (Vector)
import GHC.Generics (Generic)
import Workout.Identity.Types (WorkoutId, WorkoutRevision)
import Workout.Measurement.Types (Power)

data PowerCurve = PowerCurve
    { curveWorkoutId :: WorkoutId
    , inputRevision :: WorkoutRevision
    , method :: Text
    , maxGapSeconds :: Int
    , points :: Vector PowerCurvePoint
    }
    deriving (Eq, Show, Generic)

data PowerCurvePoint = PowerCurvePoint
    { durationSeconds :: Int
    , best :: Maybe PowerEffort
    }
    deriving (Eq, Show, Generic)

data PowerEffort = PowerEffort
    { averagePower :: Power
    , start :: UTCTime
    , end :: UTCTime
    }
    deriving (Eq, Show, Generic)
