module Workout.Cycling.Empty (emptyCycling, emptyCyclingSummary) where

import qualified Data.Vector as V
import Workout.Common.Empty
import Workout.Cycling.Types
import Workout.Measurement.Summary (emptyStatistics, reportedOnly)

emptyCyclingSummary :: CyclingSummary
emptyCyclingSummary = CyclingSummary emptyCommonSummary emptyStatistics Nothing Nothing Nothing Nothing Nothing

emptyCycling :: CyclingData
emptyCycling =
    CyclingData
        { cyclingMotion = emptyMotion
        , cyclingCadence = V.empty
        , cyclingPedaling = PedalingData V.empty V.empty V.empty V.empty V.empty
        , cyclingGearChanges = V.empty
        , cyclingSummary = reportedOnly emptyCyclingSummary
        , cyclingLaps = V.empty
        , cyclingContext = CyclingContext Nothing Nothing Nothing Nothing
        }
