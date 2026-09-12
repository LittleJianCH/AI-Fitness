{-# LANGUAGE OverloadedStrings #-}

module StatisticsTests (cases) where

import Data.Maybe (isNothing)
import qualified Data.Vector as V
import qualified Fixtures as F
import Workout.Empty
import Workout.Measurement.Calculate (sampleStatistics)
import qualified Workout.Sport as Sport
import qualified Workout.Statistics as Stats
import Workout.Types
import qualified Workout.Validation as Validation

cases :: [(String, Bool)]
cases =
    [
        ( "statistics: long streams fold without accumulating deferred means"
        , averageValue (sample [(t, 42) | t <- [0 .. 100000]]) == Just 42
        )
    , ("statistics: empty has no invented values", sample [] == Statistics Nothing Nothing Nothing)
    ,
        ( "statistics: singleton has extrema without a mean"
        , sample [(0, 7)] == Statistics (Just 7) Nothing (Just 7)
        )
    ,
        ( "statistics: real zero participates in mean"
        , sample [(0, 0), (10, 20)] == Statistics (Just 0) (Just 10) (Just 20)
        )
    ,
        ( "statistics: irregular intervals are time weighted"
        , averageValue (sample [(0, 0), (10, 20), (40, 20)]) == Just 17.5
        )
    , ("statistics: exactly 120 seconds is covered", averageValue (sample [(0, 0), (120, 20)]) == Just 10)
    ,
        ( "statistics: long gaps excluded but isolated extrema retained"
        , sample [(0, 0), (10, 20), (131, 100)] == Statistics (Just 0) (Just 10) (Just 100)
        )
    ,
        ( "statistics: disconnected covered intervals share weighting"
        , averageValue (sample [(0, 0), (10, 20), (131, 20), (161, 20)]) == Just 17.5
        )
    ,
        ( "statistics: only disconnected samples have no mean"
        , isNothing (averageValue (sample [(0, 0), (121, 20)]))
        )
    ,
        ( "statistics: negative altitude is meaningful"
        , sample [(0, -10), (10, 0)] == Statistics (Just (-10)) (Just (-5)) (Just 0)
        )
    ,
        ( "statistics: large finite values do not overflow"
        , sample [(0, 1.7e308), (10, 1.7e308), (20, 1.7e308)]
            == Statistics (Just 1.7e308) (Just 1.7e308) (Just 1.7e308)
        )
    ,
        ( "statistics: opposite large finite values remain finite"
        , averageValue (sample [(0, -1.7e308), (10, 1.7e308)]) == Just 0
        )
    ,
        ( "statistics: source observation and user data retained"
        , source computed == source F.workout && workoutUserData computed == workoutUserData F.workout
        )
    , ("statistics: calculated result validates", null (Validation.validateWorkout computed))
    ,
        ( "statistics: fresh cache matches input and algorithm"
        , Stats.isCurrent computed && not (Stats.isCurrent F.workout)
        )
    ,
        ( "statistics: revision change invalidates cache"
        , not (Stats.isCurrent computed {workoutRevision = WorkoutRevision 2})
        )
    , ("statistics: computation time is supplied", fmap calculatedAt cyclingResult == Just (F.at 20000))
    ,
        ( "statistics: ignores device averages, maxima and workout boundaries"
        , fmap (summaryHeartRate . cyclingCommonSummary . calculationValue) cyclingResult
            == Just (Statistics (Just (HeartRate 122)) (Just (HeartRate 141)) (Just (HeartRate 160)))
        )
    ,
        ( "statistics: streams are independent"
        , fmap (summaryPower . cyclingCommonSummary . calculationValue) cyclingResult
            == Just (Statistics (Just (Power 0)) (Just (Power 41)) (Just (Power 82)))
        )
    ,
        ( "statistics: device-only metrics stay absent"
        , fmap (summaryTemperature . cyclingCommonSummary . calculationValue) cyclingResult
            == Just emptyStatistics
        )
    ,
        ( "statistics: unrelated aggregates are not copied"
        , fmap (summaryDistance . cyclingCommonSummary . calculationValue) cyclingResult == Just Nothing
        )
    ,
        ( "statistics: singleton cadence preserves zero"
        , fmap (summaryCyclingCadence . calculationValue) cyclingResult
            == Just (Statistics (Just (CyclingCadence 0)) Nothing (Just (CyclingCadence 0)))
        )
    ,
        ( "statistics: running cadence retains both-feet units"
        , fmap (summaryRunningCadence . calculationValue) runningResult
            == Just
                (Statistics (Just (RunningCadence 160)) (Just (RunningCadence 166)) (Just (RunningCadence 172)))
        )
    ,
        ( "statistics: algorithm upgrades invalidate old caches"
        , not (Stats.isCurrent (mapCalculation (\c -> c {calculationMethod = "old-method"}) computed))
        )
    ,
        ( "statistics: configuration changes invalidate old caches"
        , not (Stats.isCurrent (mapCalculation (\c -> c {calculationConfig = "old-config"}) computed))
        )
    , ("statistics: running dynamics keep independent time support", dynamicsCheck)
    ]
  where
    sample :: [(Integer, Double)] -> Statistics Double
    sample = sampleStatistics . V.fromList . map (\(t, x) -> Timed (F.at t) x)
    computed = Stats.calculate (F.at 20000) F.workout
    source = Sport.invalidateCalculated . observationSport . workoutObservation
    cyclingResult = case observationSport (workoutObservation computed) of
        Cycling dat -> calculatedSummary (cyclingSummary dat)
        Running _ -> Nothing
    runningResult = case observationSport (workoutObservation (Stats.calculate (F.at 20000) F.runningWorkout)) of
        Running dat -> calculatedSummary (runningSummary dat)
        Cycling _ -> Nothing

mapCalculation :: (Calculated CyclingSummary -> Calculated CyclingSummary) -> Workout -> Workout
mapCalculation f workout = workout {workoutObservation = observation {observationSport = sport}}
  where
    observation = workoutObservation workout
    sport = case observationSport observation of
        Cycling dat ->
            Cycling
                dat
                    { cyclingSummary =
                        (cyclingSummary dat) {calculatedSummary = f <$> calculatedSummary (cyclingSummary dat)}
                    }
        other -> other

dynamicsCheck :: Bool
dynamicsCheck = case observationSport (workoutObservation (Stats.calculate F.start workout)) of
    Running dat -> case calculationValue <$> calculatedSummary (runningSummary dat) of
        Just summary ->
            summaryStepLength summary == Statistics (Just (Distance 1)) (Just (Distance 2)) (Just (Distance 3))
                && summaryVerticalOscillation summary == Statistics (Just (Distance 0)) Nothing (Just (Distance 0))
                && summaryGroundContactTime summary == Statistics (Just (Duration 0.2)) Nothing (Just (Duration 0.4))
        Nothing -> False
    Cycling _ -> False
  where
    dynamics =
        RunningDynamics
            (V.fromList [Timed (F.at 18001) (Distance 1), Timed (F.at 18003) (Distance 3)])
            (V.singleton (Timed (F.at 18004) (Distance 0)))
            (V.fromList [Timed (F.at 18000) (Duration 0.2), Timed (F.at 18121) (Duration 0.4)])
    workout =
        F.runningWorkout
            { workoutObservation =
                (workoutObservation F.runningWorkout)
                    { observationSport = Running F.run {runningDynamics = dynamics}
                    }
            }
