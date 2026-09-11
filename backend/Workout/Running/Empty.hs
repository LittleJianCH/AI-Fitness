module Workout.Running.Empty (emptyRunning, emptyRunningSummary) where

import qualified Data.Vector as V
import Workout.Common.Empty
import Workout.Measurement.Summary (emptyStatistics, reportedOnly)
import Workout.Running.Types

emptyRunningSummary :: RunningSummary
emptyRunningSummary = RunningSummary emptyCommonSummary emptyStatistics emptyStatistics emptyStatistics emptyStatistics

emptyRunning :: RunningData
emptyRunning =
    RunningData
        emptyMotion
        V.empty
        (RunningDynamics V.empty V.empty V.empty)
        (reportedOnly emptyRunningSummary)
        V.empty
