{-# LANGUAGE DeriveGeneric #-}

module Workout.Running.Types
    ( RunningData (..)
    , RunningDynamics (..)
    , RunningSummary (..)
    ) where

import Data.Vector (Vector)
import GHC.Generics (Generic)
import Workout.Common.Types
import Workout.Measurement.Types

-- The initial running baseline is heart rate, altitude and GPS in runningMotion,
-- plus runningCadence (total steps/minute). Every stream is independently
-- sampled; additional motion metrics and running dynamics remain optional data.
data RunningData = RunningData
    { runningMotion :: MotionData
    , runningCadence :: TimeSeries RunningCadence
    , runningDynamics :: RunningDynamics
    , runningSummary :: Summaries RunningSummary
    , runningLaps :: Vector (Lap RunningSummary)
    }
    deriving (Eq, Show, Generic)

data RunningDynamics = RunningDynamics
    { stepLength :: TimeSeries Distance -- distance per step, not per two-step stride
    , verticalOscillation :: TimeSeries Distance
    , groundContactTime :: TimeSeries Duration
    }
    deriving (Eq, Show, Generic)

data RunningSummary = RunningSummary
    { runningCommonSummary :: CommonSummary
    , summaryRunningCadence :: Statistics RunningCadence
    , summaryStepLength :: Statistics Distance
    , summaryVerticalOscillation :: Statistics Distance
    , summaryGroundContactTime :: Statistics Duration
    }
    deriving (Eq, Show, Generic)
