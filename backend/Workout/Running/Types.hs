module Workout.Running.Types
    ( RunningData (..)
    , RunningDynamics (..)
    , RunningSummary (..)
    ) where

import Data.Vector (Vector)
import Workout.Common.Types
import Workout.Measurement.Types

data RunningData = RunningData
    { runningMotion :: MotionData
    , runningCadence :: TimeSeries RunningCadence
    , runningDynamics :: RunningDynamics
    , runningSummary :: Summaries RunningSummary
    , runningLaps :: Vector (Lap RunningSummary)
    }
    deriving (Eq, Show)

data RunningDynamics = RunningDynamics
    { stepLength :: TimeSeries Distance -- distance per step, not per two-step stride
    , verticalOscillation :: TimeSeries Distance
    , groundContactTime :: TimeSeries Duration
    }
    deriving (Eq, Show)

data RunningSummary = RunningSummary
    { runningCommonSummary :: CommonSummary
    , summaryRunningCadence :: Statistics RunningCadence
    , summaryStepLength :: Statistics Distance
    , summaryVerticalOscillation :: Statistics Distance
    , summaryGroundContactTime :: Statistics Duration
    }
    deriving (Eq, Show)
