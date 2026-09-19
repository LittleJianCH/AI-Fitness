module Analysis.HeartRate.Timing (activeRanges, intersectRanges, rangeDuration) where

import Analysis.HeartRate.Types (TimingBasis (..))
import Data.Time (NominalDiffTime, diffUTCTime)
import qualified Data.Vector as V
import Workout.Types

-- Half-open intervals; tied events retain canonical order. The first timer
-- event establishes initial state: start => stopped, stop => running.
activeRanges :: WorkoutObservation -> (TimingBasis, [TimeRange])
activeRanges observation = case timers of
    [] -> (ElapsedTimeFallback, [range])
    Timed _ first : _ -> (RecordedTimer, go (first == TimerStopped) (rangeStart range) timers)
  where
    range = observationRange observation
    timers =
        filter
            (\t -> value t == TimerStarted || value t == TimerStopped)
            (V.toList (observationEvents observation))
    go running previous [] = [TimeRange previous (rangeEnd range) | running && previous < rangeEnd range]
    go running previous (Timed time event : rest)
        | running == (event == TimerStarted) = go running previous rest
        | otherwise =
            [TimeRange previous time | running && previous < time]
                ++ go (event == TimerStarted) time rest

-- Both inputs are disjoint, ordered interval lists. Sweep rather than checking
-- every sample against every timer interval.
intersectRanges :: [(TimeRange, a)] -> [TimeRange] -> [(TimeRange, a)]
intersectRanges [] _ = []
intersectRanges _ [] = []
intersectRanges xs@((x, a) : xt) ys@(y : yt)
    | rangeEnd x <= rangeStart y = intersectRanges xt ys
    | rangeEnd y <= rangeStart x = intersectRanges xs yt
    | otherwise =
        (TimeRange (max (rangeStart x) (rangeStart y)) (min (rangeEnd x) (rangeEnd y)), a)
            : if rangeEnd x <= rangeEnd y then intersectRanges xt ys else intersectRanges xs yt

rangeDuration :: TimeRange -> NominalDiffTime
rangeDuration range = diffUTCTime (rangeEnd range) (rangeStart range)
