module Workout.Running.Update (invalidateCalculated) where

import Workout.Measurement.Summary (clearCalculated, clearLapCalculated)
import Workout.Running.Types

invalidateCalculated :: RunningData -> RunningData
invalidateCalculated dat =
    dat
        { runningSummary = clearCalculated (runningSummary dat)
        , runningLaps = clearLapCalculated <$> runningLaps dat
        }
