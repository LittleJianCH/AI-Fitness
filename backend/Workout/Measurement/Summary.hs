module Workout.Measurement.Summary (emptyStatistics, reportedOnly, clearCalculated, clearLapCalculated) where

import Workout.Measurement.Types

emptyStatistics :: Statistics a
emptyStatistics = Statistics Nothing Nothing Nothing

reportedOnly :: a -> Summaries a
reportedOnly x = Summaries x Nothing

clearCalculated :: Summaries a -> Summaries a
clearCalculated s = s {calculatedSummary = Nothing}

clearLapCalculated :: Lap a -> Lap a
clearLapCalculated l = l {lapSummary = clearCalculated (lapSummary l)}
