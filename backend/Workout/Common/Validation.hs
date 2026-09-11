{-# LANGUAGE OverloadedStrings #-}

module Workout.Common.Validation (commonSummary, motionErrors) where

import Workout.Common.Types
import Workout.Measurement.Types
import Workout.Measurement.Validation
import Workout.Validation.Types

commonSummary :: CommonSummary -> [ValidationError]
commonSummary s =
    concat
        [ optional "elapsed" (summaryElapsedTime s)
        , optional "timer" (summaryTimerTime s)
        , optional "moving" (summaryMovingTime s)
        , optional "distance" (summaryDistance s)
        , statistics "heartRate" (summaryHeartRate s)
        , statistics "speed" (summarySpeed s)
        , statistics "power" (summaryPower s)
        , statistics "altitude" (summaryAltitude s)
        , statistics "temperature" (summaryTemperature s)
        , statistics "grade" (summaryGrade s)
        , optional "ascent" (summaryAscent s)
        , optional "descent" (summaryDescent s)
        , optional "mechanicalWork" (summaryMechanicalWork s)
        , optional "metabolicEnergy" (summaryMetabolicEnergy s)
        , optional "normalizedPower" (summaryNormalizedPower s)
        , optional "intensityFactor" (summaryIntensityFactor s)
        , optional "trainingStress" (summaryTrainingStress s)
        , timeLimit "timer" (summaryTimerTime s)
        , timeLimit "moving" (summaryMovingTime s)
        ]
  where
    timeLimit field duration = case (duration, summaryElapsedTime s) of
        (Just d, Just elapsed) -> check field "Duration exceeds elapsed time" (d <= elapsed)
        _ -> []

motionErrors :: TimeRange -> MotionData -> [ValidationError]
motionErrors r m =
    concat
        [ series "heartRate" r (motionHeartRate m)
        , series "power" r (motionPower m)
        , series "speed" r (motionSpeed m)
        , cumulative "distance" r (motionDistance m)
        , series "position" r (motionPosition m)
        , series "altitude" r (motionAltitude m)
        , series "grade" r (motionGrade m)
        , cumulative "metabolicEnergy" r (motionEnergy m)
        , series "temperature" r (ambientTemperature env)
        , series "windSpeed" r (windSpeed env)
        , series "windFrom" r (windFrom env)
        , series "humidity" r (relativeHumidity env)
        ]
  where
    env = motionEnvironment m
