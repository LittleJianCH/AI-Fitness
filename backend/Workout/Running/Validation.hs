{-# LANGUAGE OverloadedStrings #-}

module Workout.Running.Validation (validateRunning, validateRunningRevision) where

import qualified Data.Vector as V
import Workout.Common.Validation
import Workout.Identity.Types
import Workout.Measurement.Types
import Workout.Measurement.Validation
import Workout.Running.Types
import Workout.Validation.Types

runningStats :: RunningSummary -> [ValidationError]
runningStats s =
    commonSummary (runningCommonSummary s)
        ++ concat
            [ statistics "cadence" (summaryRunningCadence s)
            , statistics "stepLength" (summaryStepLength s)
            , statistics "verticalOscillation" (summaryVerticalOscillation s)
            , statistics "groundContactTime" (summaryGroundContactTime s)
            ]

validateRunning :: TimeRange -> RunningData -> [ValidationError]
validateRunning r run =
    motionErrors r (runningMotion run)
        ++ concat
            [ series "cadence" r (runningCadence run)
            , series "stepLength" r (stepLength dynamics)
            , series "verticalOscillation" r (verticalOscillation dynamics)
            , series "groundContactTime" r (groundContactTime dynamics)
            , summaries runningStats (runningSummary run)
            , laps runningStats r (runningLaps run)
            ]
  where
    dynamics = runningDynamics run

validateRunningRevision :: WorkoutRevision -> RunningData -> [ValidationError]
validateRunningRevision revision dat =
    calculatedRevisionErrors revision "running.summary" (runningSummary dat)
        ++ concatMap
            (calculatedRevisionErrors revision "running.lap" . lapSummary)
            (V.toList (runningLaps dat))
