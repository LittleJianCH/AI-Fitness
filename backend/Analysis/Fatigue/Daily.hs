module Analysis.Fatigue.Daily (summarizeDays) where

import Analysis.Fatigue.Types
import Analysis.HeartRate.Calculate
import Analysis.HeartRate.Types
import Control.Monad (unless, when)
import Data.Bifunctor (first)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes)
import qualified Data.Set as Set
import Data.Time (Day, UTCTime, diffDays)
import Workout.Types

-- Caller owns calendar/timezone and supplies complete owner-filtered history.
-- Attribute the entire session to its local start date (also across midnight).
-- Missing dates between supplied endpoints are explicit unknown recording days.
summarizeDays
    :: (UTCTime -> Day)
    -> CoveragePolicy
    -> HrssProfiles
    -> [HistoryDay]
    -> Either FatigueError [DailyLoad]
summarizeDays localDay policy profiles input = do
    first HeartRateFailure (validatePolicy policy >> validateProfiles profiles)
    ordered <- validateDays
    case ordered of
        [] -> Left EmptyHistory
        firstDay : rest -> do
            let finalDay = foldl' (\_ d -> historyDate d) (historyDate firstDay) rest
            unless (diffDays finalDay (historyDate firstDay) < 36525) (Left HistoryTooLong)
            let byDay = Map.fromList [(historyDate d, d) | d <- ordered]
            traverse
                (calculate . (\day -> Map.findWithDefault (HistoryDay day IncompleteRecording []) day byDay))
                [historyDate firstDay .. finalDay]
  where
    validateDays = do
        _ <- foldl' check (Right (Set.empty, Set.empty)) input
        pure (sortOn historyDate input)
    check acc entry = do
        (days, workouts) <- acc
        let date = historyDate entry
        unless (Set.notMember date days) (Left (DuplicateDay date))
        seen <- foldl' (checkWorkout date) (Right workouts) (dayWorkouts entry)
        pure (Set.insert date days, seen)
    checkWorkout date acc workout = do
        seen <- acc
        let wid = workoutId workout
            actual = localDay (rangeStart (observationRange (workoutObservation workout)))
        unless (Set.notMember wid seen) (Left (DuplicateWorkout wid))
        unless (date == actual) (Left (WrongWorkoutDay wid date actual))
        pure (Set.insert wid seen)
    calculate entry = do
        contributions <-
            first HeartRateFailure (traverse (calculateWorkoutLoad policy profiles) (dayWorkouts entry))
        let amounts = amount . loadAvailability <$> contributions
            known = sum (catMaybes amounts)
            total = if recordingStatus entry == CompleteRecording then sum <$> sequence amounts else Nothing
        when (isNaN known || isInfinite known) (Left (NonFiniteDailyLoad (historyDate entry)))
        pure (DailyLoad (historyDate entry) (recordingStatus entry) contributions known total)
    amount availability = case availability of
        AvailableLoad n -> Just n
        ExcludedWorkout -> Just 0
        NoActiveTime -> Just 0
        _ -> Nothing
