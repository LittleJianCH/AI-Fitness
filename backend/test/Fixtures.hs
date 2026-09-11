{-# LANGUAGE OverloadedStrings #-}

module Fixtures
    ( start
    , at
    , wid
    , otherId
    , rideRange
    , rideSummary
    , ride
    , observation
    , workout
    , group
    , importRecord
    , ridePart
    , runPart
    , singleOutput
    , groupedOutput
    , runningWorkout
    ) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Time (UTCTime (..), addUTCTime, fromGregorian)
import qualified Data.UUID.Types as UUID
import qualified Data.Vector as V
import Import.Types
import Workout.Empty
import Workout.Types

start :: UTCTime
start = UTCTime (fromGregorian 2026 9 5) (5 * 3600 + 55 * 60 + 32)

at :: Integer -> UTCTime
at seconds = addUTCTime (fromInteger seconds) start

wid :: WorkoutId
wid = WorkoutId (UUID.fromWords 0 0 0 1)

otherId :: WorkoutId
otherId = WorkoutId (UUID.fromWords 0 0 0 2)

rideRange :: TimeRange
rideRange = TimeRange start (at 17442)

-- Representative values supplied by the user, not a claim to have decoded FIT.
-- Samples below are synthetic sparse examples; summary values are independent.
rideSummary :: CyclingSummary
rideSummary =
    emptyCyclingSummary
        { cyclingCommonSummary =
            emptyCommonSummary
                { summaryElapsedTime = Just (Duration 17442)
                , summaryTimerTime = Just (Duration 11642)
                , summaryMovingTime = Just (Duration 11642)
                , summaryDistance = Just (Distance 75470)
                , summaryHeartRate = Statistics (Just (HeartRate 122)) (Just (HeartRate 160)) (Just (HeartRate 186))
                , summarySpeed = Statistics Nothing (Just (Speed (23.34 / 3.6))) (Just (Speed (41.84 / 3.6)))
                , summaryPower = Statistics Nothing (Just (Power 82)) (Just (Power 616))
                , summaryAltitude = Statistics (Just (Altitude 63.8)) (Just (Altitude 70.2)) (Just (Altitude 83.8))
                , summaryTemperature =
                    Statistics (Just (Temperature 28)) (Just (Temperature 32)) (Just (Temperature 38))
                , summaryGrade = Statistics (Just (Grade (-8.23))) Nothing (Just (Grade 6.55))
                , summaryAscent = Just (Distance 90)
                , summaryDescent = Just (Distance 93)
                , summaryMechanicalWork = Just (Energy 958340)
                , summaryMetabolicEnergy = Just (Energy (972 * 4184))
                , summaryNormalizedPower = Just (Power 102)
                , summaryIntensityFactor = Just (IntensityFactor 0.582)
                , summaryTrainingStress = Just (TrainingStress 109.3)
                }
        , summaryCyclingCadence =
            Statistics (Just (CyclingCadence 0)) (Just (CyclingCadence 84)) (Just (CyclingCadence 129))
        }

ride :: CyclingData
ride =
    emptyCycling
        { cyclingMotion =
            emptyMotion
                { motionHeartRate = V.fromList [Timed start (HeartRate 122), Timed (at 2) (HeartRate 160)]
                , motionPower = V.fromList [Timed start (Power 0), Timed (at 1) (Power 82)]
                , motionDistance = V.fromList [Timed start (Distance 0), Timed (at 17442) (Distance 75470)]
                , motionPosition = V.singleton (Timed start (Position 31.2 121.5))
                , motionAltitude = V.singleton (Timed start (Altitude (-2)))
                , motionGrade = V.singleton (Timed start (Grade (-8.23)))
                , motionEnergy = V.singleton (Timed (at 17442) (Energy (972 * 4184)))
                , motionEnvironment =
                    emptyEnvironment
                        { windSpeed = V.singleton (Timed start (Speed 2.799))
                        , windFrom = V.singleton (Timed start (Bearing 359))
                        , relativeHumidity = V.singleton (Timed start (Percentage 50))
                        }
                }
        , cyclingCadence = V.singleton (Timed start (CyclingCadence 0))
        , cyclingPedaling =
            PedalingData
                (V.singleton (Timed start (Percentage 48)))
                (V.singleton (Timed start (Percentage 92)))
                (V.singleton (Timed start (Percentage 85)))
                (V.singleton (Timed start (Percentage 0)))
                (V.singleton (Timed start (Percentage 0)))
        , cyclingGearChanges =
            V.fromList
                [ Timed start (GearChange (Just (Gear Nothing (Just 34))) Nothing)
                , Timed start (GearChange Nothing (Just (Gear (Just 1) (Just 30))))
                ]
        , cyclingSummary = reportedOnly rideSummary
        , cyclingLaps =
            V.singleton
                ( Lap
                    (TimeRange start (at 1000))
                    (Just "Lap 1")
                    (reportedOnly emptyCyclingSummary)
                    V.empty
                )
        , cyclingContext =
            CyclingContext (Just "road") (Just "Gravel520") (Just (Mass 10)) (Just (Distance 2.096))
        }

observation :: WorkoutObservation
observation =
    WorkoutObservation
        { observationRange = rideRange
        , observationSport = Cycling ride
        , observationEvents =
            V.fromList
                [ Timed start TimerStarted
                , Timed (at 100) TimerStopped
                , Timed (at 100) (UserMarker Nothing)
                , Timed (at 110) TimerStarted
                , Timed (at 17442) TimerStopped
                ]
        , observationCoursePoints =
            V.singleton (CoursePoint (Just "Start") (Position 31.2 121.5) (Just start) RouteStart)
        , observationAthlete = AthleteContext (Just (Distance 1.78)) (Just (Mass 70)) (Just (Power 175))
        , observationExtensions =
            V.singleton
                ( ExtensionField
                    "skin.temperature"
                    "Skin temperature"
                    (NumericExtension (Just "degC") V.empty emptyStatistics)
                )
        , observationDataIssues =
            V.singleton
                ( DataIssue
                    "cycling.pedaling.torqueEffectiveness"
                    (Just rideRange)
                    "All reported values are zero; interpretation uncertain"
                )
        }

workout :: Workout
workout =
    Workout
        wid
        (WorkoutRevision 1)
        observation
        ( WorkoutUserData
            (Just "My ride")
            (Just "Keep my notes")
            (V.singleton "weekend")
            ExcludeFromStatistics
        )

group :: WorkoutGroup
group = WorkoutGroup (WorkoutGroupId (UUID.fromWords 0 0 0 3)) "Weekend" Nothing (wid :| [otherId])

importRecord :: ImportRecord
importRecord =
    ImportRecord
        { importId = ImportId (UUID.fromWords 0 0 0 4)
        , importKey =
            ImportKey
                (ImportOwnerId (UUID.fromWords 0 0 0 5))
                (FitContentHash "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        , archivedRawPath = Just "/private/archive/example.fit"
        , lastSuccessfulImport = Just (ImportSuccess singleOutput (ImportVersion "normalize-v1") start)
        , lastImportAttempt = ImportSucceeded start
        , suppressedAt = Nothing
        , importedDevices =
            V.singleton
                (DeviceInfo (Just "MAGENE") (Just "C706") Nothing (Just "20.1") (Just "bike computer") Nothing)
        }

ridePart, runPart :: ImportPartKey
ridePart = ImportPartKey "ride"
runPart = ImportPartKey "run"

singleOutput, groupedOutput :: ImportOutput
singleOutput = SingleWorkout (ImportedWorkout ridePart wid)
groupedOutput =
    GroupedWorkouts
        (workoutGroupId group)
        (ImportedWorkout ridePart wid :| [ImportedWorkout runPart otherId])

runningWorkout :: Workout
runningWorkout =
    Workout
        otherId
        (WorkoutRevision 1)
        ( observation
            { observationRange = TimeRange (at 18000) (at 19000)
            , observationSport = Running emptyRunning
            , observationEvents = V.empty
            , observationCoursePoints = V.empty
            , observationExtensions = V.empty
            , observationDataIssues = V.empty
            }
        )
        (WorkoutUserData (Just "My run") (Just "Keep running notes") V.empty IncludeInStatistics)
