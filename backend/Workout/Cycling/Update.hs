module Workout.Cycling.Update (invalidateCalculated) where

import Workout.Cycling.Types
import Workout.Measurement.Summary (clearCalculated, clearLapCalculated)

invalidateCalculated :: CyclingData -> CyclingData
invalidateCalculated dat =
    dat
        { cyclingSummary = clearCalculated (cyclingSummary dat)
        , cyclingLaps = clearLapCalculated <$> cyclingLaps dat
        }
