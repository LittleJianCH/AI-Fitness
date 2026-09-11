module Workout.Common.Types
    ( MotionData (..)
    , EnvironmentData (..)
    , CommonSummary (..)
    ) where

import Workout.Measurement.Types

-- Shared structure stays inside Sport. Operations are defined in Workout.Sport.
data MotionData = MotionData
    { motionHeartRate :: TimeSeries HeartRate
    , motionPower :: TimeSeries Power
    , motionSpeed :: TimeSeries Speed
    , motionDistance :: TimeSeries Distance -- cumulative from workout start
    , motionPosition :: TimeSeries Position
    , motionAltitude :: TimeSeries Altitude
    , motionGrade :: TimeSeries Grade
    , motionEnergy :: TimeSeries Energy -- cumulative metabolic energy, not mechanical work
    , motionEnvironment :: EnvironmentData
    }
    deriving (Eq, Show)

data EnvironmentData = EnvironmentData
    { ambientTemperature :: TimeSeries Temperature
    , windSpeed :: TimeSeries Speed
    , windFrom :: TimeSeries Bearing
    , relativeHumidity :: TimeSeries Percentage
    }
    deriving (Eq, Show)

data CommonSummary = CommonSummary
    { summaryElapsedTime :: Maybe Duration
    , summaryTimerTime :: Maybe Duration
    , summaryMovingTime :: Maybe Duration
    , summaryDistance :: Maybe Distance
    , summaryHeartRate :: Statistics HeartRate
    , summarySpeed :: Statistics Speed
    , summaryPower :: Statistics Power
    , summaryAltitude :: Statistics Altitude
    , summaryTemperature :: Statistics Temperature
    , summaryGrade :: Statistics Grade
    , summaryAscent :: Maybe Distance
    , summaryDescent :: Maybe Distance
    , summaryMechanicalWork :: Maybe Energy
    , summaryMetabolicEnergy :: Maybe Energy
    , summaryNormalizedPower :: Maybe Power
    , summaryIntensityFactor :: Maybe IntensityFactor
    , summaryTrainingStress :: Maybe TrainingStress
    }
    deriving (Eq, Show)
