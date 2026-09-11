{-# LANGUAGE OverloadedStrings #-}

module Workout.Cycling.Validation (validateCycling, validateCyclingRevision) where

import Data.Maybe (isJust)
import qualified Data.Vector as V
import Workout.Common.Validation
import Workout.Cycling.Types
import Workout.Identity.Types
import Workout.Measurement.Types
import Workout.Measurement.Validation
import Workout.Validation.Types

cyclingStats :: CyclingSummary -> [ValidationError]
cyclingStats s =
    commonSummary (cyclingCommonSummary s)
        ++ concat
            [ statistics "cadence" (summaryCyclingCadence s)
            , optional "leftPowerShare" (summaryLeftPowerShare s)
            , optional "leftSmoothness" (summaryLeftSmoothness s)
            , optional "rightSmoothness" (summaryRightSmoothness s)
            , optional "leftTorqueEffectiveness" (summaryLeftTorqueEffectiveness s)
            , optional "rightTorqueEffectiveness" (summaryRightTorqueEffectiveness s)
            ]

gearErrors :: GearChange -> [ValidationError]
gearErrors g =
    check
        "gearChange"
        "At least one gear must be known"
        (isJust (frontGear g) || isJust (rearGear g))
        ++ maybe [] (prefix "front" . gear) (frontGear g)
        ++ maybe [] (prefix "rear" . gear) (rearGear g)
  where
    gear x =
        check
            "gear"
            "Gear requires an index or tooth count"
            (isJust (gearIndex x) || isJust (gearTeeth x))
            ++ check "index" "Gear index must be positive" (maybe True (> 0) (gearIndex x))
            ++ check "teeth" "Tooth count must be positive" (maybe True (> 0) (gearTeeth x))

validateCycling :: TimeRange -> CyclingData -> [ValidationError]
validateCycling r c =
    motionErrors r (cyclingMotion c)
        ++ concat
            [ series "cadence" r (cyclingCadence c)
            , series "leftPowerShare" r (leftPowerShare pedal)
            , series "leftSmoothness" r (leftSmoothness pedal)
            , series "rightSmoothness" r (rightSmoothness pedal)
            , series "leftTorqueEffectiveness" r (leftTorqueEffectiveness pedal)
            , series "rightTorqueEffectiveness" r (rightTorqueEffectiveness pedal)
            , events "gearChanges" r gearErrors (cyclingGearChanges c)
            , summaries cyclingStats (cyclingSummary c)
            , laps cyclingStats r (cyclingLaps c)
            , optional "bicycleMass" (bicycleMass context)
            , optional "wheelCircumference" (wheelCircumference context)
            , check
                "wheelCircumference"
                "Wheel circumference must be positive"
                (maybe True (\(Distance x) -> positive x) (wheelCircumference context))
            ]
  where
    pedal = cyclingPedaling c
    context = cyclingContext c

validateCyclingRevision :: WorkoutRevision -> CyclingData -> [ValidationError]
validateCyclingRevision revision dat =
    calculatedRevisionErrors revision "cycling.summary" (cyclingSummary dat)
        ++ concatMap
            (calculatedRevisionErrors revision "cycling.lap" . lapSummary)
            (V.toList (cyclingLaps dat))
