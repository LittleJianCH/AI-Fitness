module AnalysisTests (cases) where

import qualified AnalysisFixtures as A
import Data.Maybe (isNothing)
import qualified Data.Vector as V
import qualified Fixtures as F
import Profile.Settings (emptySettings)
import Workout.Analysis.Calculate (calculate)
import Workout.Analysis.Heart (analyseHeart)
import Workout.Analysis.Power (analysePower, normalizedPower)
import Workout.Analysis.Series
import Workout.Analysis.Splits
import Workout.Analysis.Types
import Workout.Empty
import Workout.Types

cases :: [(String, Bool)]
cases =
    [ ("analysis: empty streams remain missing", null (analysisMetrics (calculate emptyWorkout)))
    ,
        ( "analysis: recorded timer remains known without a heart-rate profile"
        , let result = analyseHeart emptySettings A.paused
           in heartLoadStatus result == HeartProfileMissing
                && heartUsesRecordedTimer result
                && isNothing (heartHrss result)
                && isNothing (heartCoverageFraction result)
        )
    ,
        ( "analysis: missing profile does not invent recorded timer events"
        , let result = analyseHeart emptySettings A.ride
           in heartLoadStatus result == HeartProfileMissing && not (heartUsesRecordedTimer result)
        )
    ,
        ( "analysis: large finite constant histogram retains coverage"
        , near 10 (sum (map binSeconds (V.toList (distribution 25 (V.fromList [(0, 1e300), (10, 1e300)])))))
        )
    ,
        ( "analysis: hourly threshold power has 100 stress and 720kJ work"
        , let result =
                analysePower
                    3600
                    (AthleteContext Nothing (Just (Mass 70)) (Just (Power 200)))
                    (V.fromList [(t, 200) | t <- [0 .. 3600]])
                    (V.fromList [(t, 150) | t <- [0 .. 3600]])
           in nearMaybe 100 (powerStressScore result)
                && nearMaybe 720000 (powerWorkJoules result)
                && nearMaybe 0 (powerDecouplingPercent result)
        )
    ,
        ( "analysis: split means clip sensor intervals at distance crossings"
        , let result =
                distanceSplits
                    ( V.head
                        ( splitSets
                            (V.fromList [(0, 0), (100, 2000)])
                            (V.fromList [(0, 100), (100, 200)])
                            V.empty
                            V.empty
                            V.empty
                        )
                    )
           in V.length result == 2
                && nearMaybe 125 (splitHeartRate (result V.! 0))
                && nearMaybe 175 (splitHeartRate (result V.! 1))
        )
    ,
        ( "analysis: singleton has extrema without mean or duration"
        , let s = numericStatistics (V.singleton (0, 80))
           in minimumValue s == Just 80 && isNothing (averageValue s)
        )
    ,
        ( "analysis: irregular sampling uses elapsed duration"
        , nearMaybe 75 (average (segments 120 (V.fromList [(0, 0), (5, 100), (10, 100)])))
        )
    ,
        ( "analysis: gap cutoff is inclusive"
        , covered (segments 120 (V.fromList [(0, 50), (120, 50), (241, 50)])) == 120
        )
    ,
        ( "analysis: positive ramps retain isolated zero endpoint"
        , nearMaybe 50 (excludingZeros (segments 120 (V.fromList [(0, 0), (10, 0), (20, 100)])))
        )
    ,
        ( "analysis: zero plateaus are not missing"
        , average (segments 120 (V.fromList [(0, 0), (10, 0)])) == Just 0
        )
    ,
        ( "analysis: histogram conserves supported duration across ramp bins"
        , near
            20
            (sum (map binSeconds (V.toList (distribution 25 (V.fromList [(0, 0), (10, 100), (20, 0)])))))
        )
    ,
        ( "analysis: constant histogram includes zero duration"
        , near 10 (sum (map binSeconds (V.toList (distribution 25 (V.fromList [(0, 0), (10, 0)])))))
        )
    ,
        ( "analysis: independent clock interpolates within gap"
        , at 5 (V.fromList [(0, 10), (4, 30)]) 2 == Just 20
        )
    , ("analysis: no extrapolation", isNothing (at 5 (V.fromList [(0, 10), (4, 30)]) 5))
    ,
        ( "analysis: relationship does not bridge missing sensor"
        , relationshipSampleCount
            ( relationships
                PowerMetric
                HeartRateMetric
                (V.singleton (200, 100))
                (V.fromList [(0, 100), (400, 150)])
            )
            == 0
        )
    ,
        ( "analysis: constant relationships have no correlation"
        , isNothing (relationshipCorrelation (relationships PowerMetric HeartRateMetric plateau plateau))
        )
    , ("analysis: normalized constant power", nearMaybe 200 (fst (normalizedPower plateau)))
    ,
        ( "analysis: fractional origin preserves a complete thirty-second window"
        , let (np, count) = normalizedPower (V.fromList [(2.3 + fromIntegral i, 200) | i <- [0 .. 30 :: Int]])
           in nearMaybe 200 np && count == 1
        )
    ,
        ( "analysis: fractional origin preserves the final complete rolling window"
        , let (np, count) = normalizedPower (V.fromList [(4.1 + fromIntegral i, 200) | i <- [0 .. 60 :: Int]])
           in nearMaybe 200 np && count == 31
        )
    ,
        ( "analysis: a genuinely incomplete second does not supply a rolling window"
        , let xs = V.fromList ([(2.3 + fromIntegral i, 200) | i <- [0 .. 29 :: Int]] <> [(32.3 - 1e-6, 200)])
           in normalizedPower xs == (Nothing, 0)
        )
    ,
        ( "analysis: fractional timestamps preserve exact five-second gaps"
        , let watts = V.fromList ((0, 200) : [(0.2 + fromIntegral i * 5, 200) | i <- [0 .. 12 :: Int]])
              result = analysePower 60.2 (AthleteContext Nothing Nothing (Just (Power 200))) watts V.empty
           in near 60.2 (covered (segments 5 watts))
                && nearMaybe 200 (powerNormalized result)
                && powerNormalizationSeconds result == 31
                && nearMaybe (60.2 / 36) (powerStressScore result)
                && nearMaybe 200 (at 5 watts 32)
        )
    ,
        ( "analysis: floating tolerance never fills a real microsecond gap"
        , covered (segments 5 (V.fromList [(30.2, 200), (35.200001, 200)])) == 0
        )
    ,
        ( "analysis: fractional timestamps preserve exact split gap boundary"
        , let fractionalDistance = V.fromList [(0.2 + fromIntegral i * 120, fromIntegral i * 1000) | i <- [0 .. 12 :: Int]]
           in V.length (distanceSplits (V.head (splitSets fractionalDistance V.empty V.empty V.empty V.empty)))
                == 12
        )
    ,
        ( "analysis: isolated extreme power cannot change supported windows"
        , nearMaybe 200 (fst (normalizedPower (plateau <> V.singleton (100, 1e100))))
        )
    ,
        ( "analysis: short extreme run cannot change supported windows"
        , nearMaybe 200 (fst (normalizedPower (plateau <> V.fromList [(100, 1e100), (101, 1e100)])))
        )
    ,
        ( "analysis: fractional tail cannot change supported windows"
        , nearMaybe 200 (fst (normalizedPower (plateau <> V.singleton (60.5, 1e100))))
        )
    ,
        ( "analysis: derived streams include both sensor breakpoints"
        , nearMaybe
            (6.9 / 60)
            ( average
                ( deriveSegments
                    ratio
                    (V.fromList [(0, 1), (60, 1)])
                    (V.fromList [(0, 1), (1, 10), (59, 10), (60, 1)])
                )
            )
        )
    ,
        ( "analysis: derived streams preserve unsupported intervals"
        , let derived =
                deriveSegments
                    ratio
                    (V.fromList [(0, 1), (120, 1), (240, 1)])
                    (V.fromList [(0, 2), (10, 2), (200, 2), (240, 2)])
           in near 50 (covered derived) && nearMaybe 0.5 (average derived)
        )
    ,
        ( "analysis: normalized real zero remains zero"
        , fst (normalizedPower (V.map (\(t, _) -> (t, 0)) plateau)) == Just 0
        )
    ,
        ( "analysis: normalized power needs complete 30-second window"
        , isNothing (fst (normalizedPower (V.take 30 plateau)))
        )
    ,
        ( "analysis: gap resets rolling window"
        , isNothing
            (fst (normalizedPower (V.fromList ([(t, 200) | t <- [0 .. 20]] <> [(t, 200) | t <- [30 .. 50]]))))
        )
    ,
        ( "analysis: finite large power does not overflow fourth moment"
        , nearMaybe 1e300 (fst (normalizedPower (V.map (\(t, _) -> (t, 1e300)) plateau)))
        )
    ,
        ( "analysis: split distance and elapsed seconds"
        , case V.toList (distanceSplits (V.head sets)) of
            [a, b, c] ->
                splitDistanceMetres a == 1000
                    && splitEndSeconds a == 200
                    && splitDistanceMetres b == 1000
                    && splitDistanceMetres c == 500
                    && splitEndSeconds c == 500
            _ -> False
        )
    ,
        ( "analysis: distance gap cannot become a fabricated split"
        , all
            (V.null . distanceSplits)
            (splitSets (V.fromList [(0, 0), (500, 2500)]) V.empty V.empty V.empty V.empty)
        )
    ,
        ( "analysis: distance reset cannot become negative split"
        , all
            (V.null . distanceSplits)
            (splitSets (V.fromList [(0, 0), (60, 100), (120, 50)]) V.empty V.empty V.empty V.empty)
        )
    ,
        ( "analysis: identical halves have zero change"
        , maybe False ((== 0) . secondHalfChangePercent) (compareHalves distance)
        )
    ,
        ( "analysis: workout revision accompanies derived result"
        , analysisRevision (calculate emptyWorkout) == workoutRevision emptyWorkout
        )
    ,
        ( "analysis: missing mass and FTP are not guessed"
        , let p = analysisPower (calculate emptyWorkout)
           in isNothing (powerWattsPerKilogram p) && isNothing (powerIntensityFactor p)
        )
    ,
        ( "analysis: running dynamics derive supported flight and ratios"
        , case analysisRunning (calculate runWorkout) of
            Just result ->
                nearMaybe 0.125 (runningFlightSeconds result)
                    && nearMaybe 10 (runningVerticalRatioPercent result)
                    && nearMaybe (100 / 3) (runningFlightRatioPercent result)
                    && nearMaybe 160 (runningSteps result)
            Nothing -> False
        )
    ,
        ( "analysis: running flight follows intermediate cadence changes"
        , let original = workoutObservation runWorkout
              changed = case observationSport original of
                Running dat ->
                    Running
                        dat
                            { runningCadence =
                                V.fromList
                                    [Timed (F.at t) (RunningCadence c) | (t, c) <- [(0, 160), (1, 240), (59, 240), (60, 160)]]
                            }
                cycling -> cycling
           in case analysisRunning
                (calculate (runWorkout {workoutObservation = original {observationSport = changed}})) of
                Just result -> nearMaybe (0.125 / 60) (runningFlightSeconds result)
                Nothing -> False
        )
    ]
  where
    plateau = V.fromList [(t, 200) | t <- [0 .. 60]]
    distance = V.fromList [(t, t * 5) | t <- [0, 100 .. 500]]
    sets = splitSets distance V.empty V.empty V.empty V.empty

near :: Double -> Double -> Bool
near expected actual = abs (actual / max 1 (abs expected) - expected / max 1 (abs expected)) < 1e-9

nearMaybe :: Double -> Maybe Double -> Bool
nearMaybe expected = maybe False (near expected)

emptyWorkout :: Workout
emptyWorkout =
    F.workout
        { workoutObservation =
            F.observation
                { observationRange = TimeRange F.start (F.at 60)
                , observationSport = Cycling emptyCycling
                , observationAthlete = AthleteContext Nothing Nothing Nothing
                , observationEvents = V.empty
                }
        , workoutUserData = emptyUserData
        }

runWorkout :: Workout
runWorkout =
    emptyWorkout
        { workoutObservation =
            (workoutObservation emptyWorkout)
                { observationSport =
                    Running
                        emptyRunning
                            { runningCadence =
                                V.fromList [Timed F.start (RunningCadence 160), Timed (F.at 60) (RunningCadence 160)]
                            , runningDynamics =
                                RunningDynamics
                                    (V.fromList [Timed F.start (Distance 1), Timed (F.at 60) (Distance 1)])
                                    (V.fromList [Timed F.start (Distance 0.1), Timed (F.at 60) (Distance 0.1)])
                                    (V.fromList [Timed F.start (Duration 0.25), Timed (F.at 60) (Duration 0.25)])
                            }
                }
        }
