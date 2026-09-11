module Workout.Common.Empty (emptyEnvironment, emptyMotion, emptyCommonSummary) where

import qualified Data.Vector as V
import Workout.Common.Types
import Workout.Measurement.Summary (emptyStatistics)

emptyEnvironment :: EnvironmentData
emptyEnvironment = EnvironmentData V.empty V.empty V.empty V.empty

emptyMotion :: MotionData
emptyMotion = MotionData V.empty V.empty V.empty V.empty V.empty V.empty V.empty V.empty emptyEnvironment

emptyCommonSummary :: CommonSummary
emptyCommonSummary =
    CommonSummary
        { summaryElapsedTime = Nothing
        , summaryTimerTime = Nothing
        , summaryMovingTime = Nothing
        , summaryDistance = Nothing
        , summaryHeartRate = emptyStatistics
        , summarySpeed = emptyStatistics
        , summaryPower = emptyStatistics
        , summaryAltitude = emptyStatistics
        , summaryTemperature = emptyStatistics
        , summaryGrade = emptyStatistics
        , summaryAscent = Nothing
        , summaryDescent = Nothing
        , summaryMechanicalWork = Nothing
        , summaryMetabolicEnergy = Nothing
        , summaryNormalizedPower = Nothing
        , summaryIntensityFactor = Nothing
        , summaryTrainingStress = Nothing
        }
