{-# LANGUAGE OverloadedStrings #-}

module Workout.Analysis.Calculate (calculate, calculateWithSettings) where

import Control.Applicative ((<|>))
import Data.Maybe (mapMaybe)
import Data.Time (diffUTCTime)
import qualified Data.Vector as V
import qualified Profile.Settings as Settings
import Profile.Types
import Workout.Analysis.Heart (analyseHeart, powerZones)
import Workout.Analysis.Power (analysePower)
import Workout.Analysis.Series
import Workout.Analysis.Splits (compareHalves, splitSets)
import Workout.Analysis.Types
import qualified Workout.Sport as Sport
import Workout.Types

calculate :: Workout -> WorkoutAnalysis
calculate = calculateWithSettings Settings.emptySettings

calculateWithSettings :: UserSettings -> Workout -> WorkoutAnalysis
calculateWithSettings settings workout =
    WorkoutAnalysis
        (workoutId workout)
        (workoutRevision workout)
        "workout-analysis-v1"
        120
        (settingsRevision settings)
        body
        (analyseHeart settings workout)
        (powerZones (powerThresholdWatts power) watts)
        (V.fromList (map metric available))
        power
        running
        (splitSets distance heart watts cadence altitude)
        (compareHalves distance)
        (V.fromList comparisons)
        ( V.fromList
            [ "Sensor means and distributions use elapsed-time linear segments up to 120 seconds; real zero values remain observations. Timer pauses are not removed from sensor streams."
            , "Power normalization uses complete 30-second rolling windows on one-second integrals, resetting at gaps over five seconds. Work is limited to observed coverage."
            , "Distance splits need continuous nondecreasing distance samples. They use elapsed time and include stops."
            , "Relationships align independent sensor clocks within the maximum gap; correlation is sample-based. Display points are bounded to 600."
            ]
        )
  where
    observation = workoutObservation workout
    sport = observationSport observation
    motion = Sport.motion sport
    range = observationRange observation
    origin = rangeStart range
    elapsed = realToFrac (diffUTCTime (rangeEnd range) origin)
    heart = samples origin (motionHeartRate motion)
    watts = samples origin (motionPower motion)
    speed = samples origin (motionSpeed motion)
    distance = samples origin (motionDistance motion)
    altitude = samples origin (motionAltitude motion)
    cadence = case sport of
        Cycling dat -> samples origin (cyclingCadence dat)
        Running dat -> samples origin (runningCadence dat)
    streams =
        [ (HeartRateMetric, 10, heart)
        , (PowerMetric, 25, watts)
        , (SpeedMetric, 1, speed)
        , (CadenceMetric, 5, cadence)
        , (AltitudeMetric, 10, altitude)
        , (TemperatureMetric, 2, samples origin (ambientTemperature (motionEnvironment motion)))
        , (GradeMetric, 2, samples origin (motionGrade motion))
        ]
            <> case sport of
                Cycling _ -> []
                Running dat ->
                    let dynamics = runningDynamics dat
                     in [ (StepLengthMetric, 0.1, samples origin (stepLength dynamics))
                        , (VerticalOscillationMetric, 0.01, samples origin (verticalOscillation dynamics))
                        , (GroundContactTimeMetric, 0.025, samples origin (groundContactTime dynamics))
                        ]
    available = filter (\(_, _, xs) -> not (V.null xs)) streams
    metric (kind, width, xs) =
        MetricAnalysis
            kind
            (numericStatistics xs)
            (V.length xs)
            (covered (segments 120 xs))
            (excludingZeros (segments 120 xs))
            (distribution width xs)
    body = Settings.profileAt origin settings
    originalAthlete = observationAthlete observation
    selectedSport = case sport of Cycling _ -> bodyCycling; Running _ -> bodyRunning
    athlete =
        originalAthlete
            { athleteMass = athleteMass originalAthlete <|> (Mass <$> (body >>= bodyMassKilograms))
            , thresholdPower =
                thresholdPower originalAthlete <|> (Power <$> (body >>= sportThresholdWatts . selectedSport))
            }
    power = analysePower elapsed athlete watts heart
    comparisons =
        [ relationships x y left right
        | (x, y, left, right) <-
            [ (PowerMetric, HeartRateMetric, watts, heart)
            , (CadenceMetric, PowerMetric, cadence, watts)
            , (CadenceMetric, HeartRateMetric, cadence, heart)
            , (SpeedMetric, HeartRateMetric, speed, heart)
            ]
        , not (V.null left || V.null right)
        ]
    running = case sport of
        Cycling _ -> Nothing
        Running dat ->
            let dynamics = runningDynamics dat
                contact = samples origin (groundContactTime dynamics)
                stride = samples origin (stepLength dynamics)
                oscillation = samples origin (verticalOscillation dynamics)
                flightSamples =
                    V.fromList $
                        mapMaybe
                            ( \(t, c) -> do
                                stepsPerMinute <- at 120 cadence t
                                period <- ratio 60 stepsPerMinute
                                if c <= period then Just (t, period - c) else Nothing
                            )
                            (V.toList contact)
                verticalSamples =
                    V.fromList $
                        mapMaybe
                            ( \(t, v) -> do
                                lengthMetres <- at 120 stride t
                                value <- (* 100) <$> ratio v lengthMetres
                                pure (t, value)
                            )
                            (V.toList oscillation)
                flightRatioSamples =
                    V.fromList $
                        mapMaybe
                            ( \(t, f) -> do
                                c <- at 120 contact t
                                value <- (* 100) <$> ratio f (f + c)
                                pure (t, value)
                            )
                            (V.toList flightSamples)
                cadSpans = segments 120 cadence
                count =
                    if abs (covered cadSpans - elapsed) <= 1e-6 && elapsed > 0
                        then (/ 60) <$> integral cadSpans
                        else Nothing
                avg = average . segments 120
                effectiveness =
                    if abs (covered (segments 5 speed) - elapsed) <= 1e-6
                        && abs (covered (segments 5 watts) - elapsed) <= 1e-6
                        then (,) <$> avg speed <*> powerWattsPerKilogram power >>= uncurry ratio
                        else Nothing
             in Just
                    ( RunningAnalysis
                        count
                        (avg flightSamples)
                        (avg verticalSamples)
                        (avg flightRatioSamples)
                        effectiveness
                    )
