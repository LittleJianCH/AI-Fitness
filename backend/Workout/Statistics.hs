{-# LANGUAGE OverloadedStrings #-}

module Workout.Statistics (calculate, isCurrent, method, config) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Workout.Common.Empty (emptyCommonSummary)
import Workout.Cycling.Empty (emptyCyclingSummary)
import Workout.Measurement.Calculate (sampleStatistics)
import Workout.Running.Empty (emptyRunningSummary)
import Workout.Types

method, config :: Text
method = "sample-statistics-v1"
config = "linear-time-weighted;include-zero;max-gap-seconds=120;no-extrapolation"

-- Device summaries remain source facts. Our result is constructed only from
-- sample streams; unrelated aggregate fields are absent, not copied from devices.
calculate :: UTCTime -> Workout -> Workout
calculate now workout =
    workout {workoutObservation = observation {observationSport = calculatedSport}}
  where
    observation = workoutObservation workout
    result summary = Just (Calculated (workoutRevision workout) config method now summary)
    common m =
        emptyCommonSummary
            { summaryHeartRate = sampleStatistics (motionHeartRate m)
            , summaryPower = sampleStatistics (motionPower m)
            , summarySpeed = sampleStatistics (motionSpeed m)
            , summaryAltitude = sampleStatistics (motionAltitude m)
            , summaryGrade = sampleStatistics (motionGrade m)
            , summaryTemperature = sampleStatistics (ambientTemperature (motionEnvironment m))
            }
    calculatedSport = case observationSport observation of
        Cycling dat ->
            let summary =
                    emptyCyclingSummary
                        { cyclingCommonSummary = common (cyclingMotion dat)
                        , summaryCyclingCadence = sampleStatistics (cyclingCadence dat)
                        }
             in Cycling
                    dat
                        { cyclingSummary =
                            (cyclingSummary dat) {calculatedSummary = result summary}
                        }
        Running dat ->
            let dynamics = runningDynamics dat
                summary =
                    emptyRunningSummary
                        { runningCommonSummary = common (runningMotion dat)
                        , summaryRunningCadence = sampleStatistics (runningCadence dat)
                        , summaryStepLength = sampleStatistics (stepLength dynamics)
                        , summaryVerticalOscillation =
                            sampleStatistics (verticalOscillation dynamics)
                        , summaryGroundContactTime = sampleStatistics (groundContactTime dynamics)
                        }
             in Running
                    dat
                        { runningSummary =
                            (runningSummary dat) {calculatedSummary = result summary}
                        }

isCurrent :: Workout -> Bool
isCurrent workout = case observationSport (workoutObservation workout) of
    Cycling dat -> current (calculatedSummary (cyclingSummary dat))
    Running dat -> current (calculatedSummary (runningSummary dat))
  where
    current = maybe False $ \result ->
        calculationInputRevision result == workoutRevision workout
            && calculationMethod result == method
            && calculationConfig result == config
