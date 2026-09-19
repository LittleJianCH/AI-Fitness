{-# LANGUAGE OverloadedStrings #-}

module FatigueTests (cases) where

import Analysis.Fatigue.Calculate
import Analysis.Fatigue.Types
import Analysis.HeartRate.Calculate
import Analysis.HeartRate.Types
import AnalysisFixtures
import Data.Either (isLeft)
import Data.Maybe (isNothing)
import Data.Time
import Workout.Empty
import Workout.Types

cases :: [(String, Bool)]
cases =
    [
        ( "zero active time without profile does not poison future days"
        , case analyseFatigue
            utctDay
            defaultCoveragePolicy
            (HrssProfiles [] [])
            defaultFatigueConfig
            AssumeNoPriorLoad
            [HistoryDay day0 CompleteRecording [withEvents [(0, TimerStopped)] ride], restDay (addDays 1 day0)] of
            Right h -> (acuteLoad <$> fatiguePoints h) == [Just 0, Just 0]
            _ -> False
        )
    ,
        ( "complete empty day is known rest"
        , case analyse [restDay day0] of Right h -> (totalDailyLoad <$> dailyLoads h) == [Just 0]; _ -> False
        )
    ,
        ( "excluded workout does not require a profile"
        , case analyse
            [ HistoryDay
                day0
                CompleteRecording
                [ride {workoutUserData = emptyUserData {statisticsInclusion = ExcludeFromStatistics}}]
            ] of
            Right h -> (totalDailyLoad <$> dailyLoads h) == [Just 0]
            _ -> False
        )
    ,
        ( "two workouts sum once"
        , case analyse [HistoryDay day0 CompleteRecording [ride, run {workoutId = workoutId secondRide}]] of
            Right h -> maybe False (near 200) (totalDailyLoad =<< firstValue (dailyLoads h))
            _ -> False
        )
    ,
        ( "duplicate identity across revisions is rejected"
        , isLeft
            (analyse [HistoryDay day0 CompleteRecording [ride, ride {workoutRevision = WorkoutRevision 2}]])
        )
    , ("duplicate day is rejected", isLeft (analyse [restDay day0, restDay day0]))
    ,
        ( "wrong calendar attribution rejected"
        , isLeft (analyse [HistoryDay (addDays 1 day0) CompleteRecording [ride]])
        )
    ,
        ( "unsorted dates normalized"
        , fmap (map fatigueDate . fatiguePoints) (analyse [restDay (addDays 1 day0), restDay day0])
            == Right [day0, addDays 1 day0]
        )
    ,
        ( "omitted date is unknown, not rest"
        , case analyse [restDay day0, restDay (addDays 2 day0)] of
            Right h ->
                (totalDailyLoad <$> dailyLoads h) == [Just 0, Nothing, Just 0]
                    && (chronicLoad <$> fatiguePoints h) == [Just 0, Nothing, Nothing]
            _ -> False
        )
    ,
        ( "partial day retains known contributions but unknown total"
        , case analyse [HistoryDay day0 CompleteRecording [ride, withSamples [] secondRide]] of
            Right h ->
                maybe
                    False
                    (\d -> near 100 (knownDailyLoad d) && isNothing (totalDailyLoad d))
                    (firstValue (dailyLoads h))
            _ -> False
        )
    ,
        ( "incomplete imports cannot masquerade as complete total"
        , case analyse [HistoryDay day0 IncompleteRecording [ride]] of
            Right h ->
                maybe
                    False
                    (\d -> near 100 (knownDailyLoad d) && isNothing (totalDailyLoad d))
                    (firstValue (dailyLoads h))
            _ -> False
        )
    ,
        ( "initial state must be explicit and finite"
        , isLeft (analyseWith defaultFatigueConfig (KnownPriorLoad (0 / 0) 0) [restDay day0])
        )
    , ("empty history rejected", isLeft (analyse []))
    , ("resource-bounded calendar", isLeft (analyse [restDay day0, restDay (addDays 36525 day0)]))
    ,
        ( "invalid time constant rejected"
        , isLeft (analyseWith (FatigueConfig 7 42) AssumeNoPriorLoad [restDay day0])
        )
    ,
        ( "non-finite time constant rejected"
        , isLeft (analyseWith (FatigueConfig (1 / 0) 7) AssumeNoPriorLoad [restDay day0])
        )
    ,
        ( "cold-start impulse matches closed-form EWMA"
        , case analyse [HistoryDay day0 CompleteRecording [ride]] of
            Right h ->
                maybe
                    False
                    ( \p ->
                        nearMaybe 2.352831334775673 (chronicLoad p)
                            && nearMaybe 13.31221002498184 (acuteLoad p)
                            && nearMaybe (-10.959378690206167) (loadBalance p)
                    )
                    (firstValue (fatiguePoints h))
            _ -> False
        )
    ,
        ( "steady daily load preserves steady state"
        , case analyseWith defaultFatigueConfig (KnownPriorLoad 100 100) [HistoryDay day0 CompleteRecording [ride]] of
            Right h ->
                maybe
                    False
                    (\p -> nearMaybe 100 (chronicLoad p) && nearMaybe 100 (acuteLoad p) && nearMaybe 0 (loadBalance p))
                    (firstValue (fatiguePoints h))
            _ -> False
        )
    ,
        ( "seven rest days decay ATL by exp(-1)"
        , case analyseWith defaultFatigueConfig (KnownPriorLoad 50 100) (restDay . (`addDays` day0) <$> [0 .. 6]) of
            Right h -> maybe False (nearMaybe (100 / exp 1) . acuteLoad) (lastValue (fatiguePoints h))
            _ -> False
        )
    ,
        ( "history initialization influence is exposed"
        , case analyse (restDay . (`addDays` day0) <$> [0 .. 41]) of
            Right h -> maybe False (near (exp (-1)) . initialFitnessWeight) (lastValue (fatiguePoints h))
            _ -> False
        )
    ,
        ( "known-day load remains visible after unknown history"
        , case analyse
            [ HistoryDay day0 IncompleteRecording []
            , HistoryDay (addDays 1 day0) CompleteRecording [shiftWorkout 86400 ride]
            ] of
            Right h ->
                maybe
                    False
                    (\p -> nearMaybe 100 (trainingLoad p) && isNothing (acuteLoad p))
                    (lastValue (fatiguePoints h))
            _ -> False
        )
    ,
        ( "backfill restores calculable history"
        , case analyse [restDay day0, HistoryDay (addDays 1 day0) CompleteRecording [shiftWorkout 86400 ride]] of
            Right h -> maybe False (nearMaybe 13.31221002498184 . acuteLoad) (lastValue (fatiguePoints h))
            _ -> False
        )
    ,
        ( "deletion recomputes downstream load"
        , case analyse [restDay day0, restDay (addDays 1 day0)] of
            Right h -> all ((== Just 0) . acuteLoad) (fatiguePoints h)
            _ -> False
        )
    ,
        ( "analysis preserves algorithm/config/revision provenance"
        , case analyse [HistoryDay day0 CompleteRecording [ride]] of
            Right h ->
                heartRateMethod h == hrssMethod
                    && historyProfiles h == profiles
                    && maybe
                        False
                        ((== WorkoutRevision 1) . loadWorkoutRevision)
                        (firstValue (concatMap workoutContributions (dailyLoads h)))
            _ -> False
        )
    ,
        ( "local start date handles UTC date boundary"
        , case analyseFatigue
            (localDay . utcToLocalTime (hoursToTimeZone 8))
            defaultCoveragePolicy
            profiles
            defaultFatigueConfig
            AssumeNoPriorLoad
            [HistoryDay (addDays 1 day0) CompleteRecording [shiftWorkout (18 * 3600) ride]] of
            Right _ -> True
            _ -> False
        )
    ,
        ( "workout crossing midnight is assigned once to start day"
        , case analyse [HistoryDay day0 CompleteRecording [shiftWorkout (23 * 3600 + 1800) ride]] of
            Right h -> maybe False (near 100) (totalDailyLoad =<< firstValue (dailyLoads h))
            _ -> False
        )
    ]

analyse :: [HistoryDay] -> Either FatigueError FatigueHistory
analyse = analyseWith defaultFatigueConfig AssumeNoPriorLoad

analyseWith :: FatigueConfig -> InitialState -> [HistoryDay] -> Either FatigueError FatigueHistory
analyseWith = analyseFatigue utctDay defaultCoveragePolicy profiles
