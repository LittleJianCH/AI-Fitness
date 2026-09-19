{-# LANGUAGE OverloadedStrings #-}

module AnalysisFixtures
    ( near
    , nearMaybe
    , eitherMaybe
    , firstValue
    , lastValue
    , day0
    , epoch
    , profile
    , profiles
    , changedProfiles
    , ride
    , run
    , secondRide
    , mixed
    , irregular
    , paused
    , duplicateStarts
    , staleResume
    , restDay
    , withSamples
    , withEvents
    , shiftWorkout
    ) where

import Analysis.Fatigue.Types
import Analysis.HeartRate.Types
import Data.Time
import qualified Data.UUID.Types as UUID
import qualified Data.Vector as V
import Workout.Empty
import Workout.Types

near :: Double -> Double -> Bool
near expected actual = abs (expected - actual) <= 1e-9 * max 1 (abs expected)
nearMaybe :: Double -> Maybe Double -> Bool
nearMaybe expected = maybe False (near expected)
eitherMaybe :: Either a b -> Maybe b
eitherMaybe = either (const Nothing) Just
firstValue :: [a] -> Maybe a
firstValue [] = Nothing
firstValue (x : _) = Just x
lastValue :: [a] -> Maybe a
lastValue = firstValue . reverse

day0 :: Day
day0 = fromGregorian 2026 9 12
epoch :: UTCTime
epoch = UTCTime day0 0
profile :: HrssProfile
profile =
    HrssProfile
        "base"
        (addUTCTime (-86400) epoch)
        Nothing
        (HeartRate 60)
        (HeartRate 200)
        (HeartRate 180)
        Banister192
profiles :: HrssProfiles
profiles = HrssProfiles [profile] [profile]
changedProfiles :: HrssProfiles
changedProfiles =
    HrssProfiles
        [ profile {profileId = "new", profileFrom = epoch}
        , profile {profileId = "old", profileUntil = Just epoch}
        ]
        []
ride :: Workout
ride =
    withSamples [(t, 180) | t <- [0, 10 .. 3600]] $
        Workout
            (WorkoutId (UUID.fromWords 0 0 0 1))
            (WorkoutRevision 1)
            ( WorkoutObservation
                (TimeRange epoch (addUTCTime 3600 epoch))
                (Cycling emptyCycling)
                V.empty
                V.empty
                emptyAthlete
                V.empty
                V.empty
            )
            emptyUserData
run :: Workout
run =
    ride
        { workoutObservation =
            (workoutObservation ride)
                { observationSport =
                    Running
                        emptyRunning
                            { runningMotion =
                                emptyMotion
                                    { motionHeartRate =
                                        V.fromList [Timed (addUTCTime (fromInteger t) epoch) (HeartRate 180) | t <- [0, 10 .. 3600]]
                                    }
                            }
                }
        }
secondRide :: Workout
secondRide = ride {workoutId = WorkoutId (UUID.fromWords 0 0 0 2)}
mixed :: Workout
mixed = withSamples [(0, 120), (1800, 180), (3600, 180)] ride
irregular :: Workout
irregular =
    withSamples
        [(0, 180), (1, 180), (9, 180), (10, 180)]
        ride
            { workoutObservation =
                (workoutObservation ride) {observationRange = TimeRange epoch (addUTCTime 10 epoch)}
            }
paused :: Workout
paused = withEvents [(0, TimerStarted), (1800, TimerStopped)] ride
duplicateStarts :: Workout
duplicateStarts = withEvents [(0, TimerStarted), (5, TimerStarted)] irregular
staleResume :: Workout
staleResume =
    withEvents [(0, TimerStarted), (5, TimerStopped), (10, TimerStarted)] $
        withSamples
            [(0, 180), (5, 180), (15, 180), (20, 180)]
            ride
                { workoutObservation =
                    (workoutObservation ride) {observationRange = TimeRange epoch (addUTCTime 20 epoch)}
                }
restDay :: Day -> HistoryDay
restDay day = HistoryDay day CompleteRecording []
withSamples :: [(Integer, Double)] -> Workout -> Workout
withSamples xs w =
    w
        { workoutObservation =
            o
                { observationSport =
                    Cycling
                        emptyCycling
                            { cyclingMotion =
                                emptyMotion
                                    { motionHeartRate =
                                        V.fromList
                                            [ Timed (addUTCTime (fromInteger t) (rangeStart (observationRange o))) (HeartRate hr) | (t, hr) <- xs
                                            ]
                                    }
                            }
                }
        }
  where
    o = workoutObservation w
withEvents :: [(Integer, WorkoutEvent)] -> Workout -> Workout
withEvents xs w =
    w
        { workoutObservation =
            o {observationEvents = V.fromList [Timed (addUTCTime (fromInteger t) epoch) e | (t, e) <- xs]}
        }
  where
    o = workoutObservation w
shiftWorkout :: Integer -> Workout -> Workout
shiftWorkout delta w =
    w
        { workoutObservation =
            o
                { observationRange = TimeRange (shift (rangeStart r)) (shift (rangeEnd r))
                , observationSport =
                    Cycling
                        emptyCycling
                            { cyclingMotion =
                                emptyMotion {motionHeartRate = V.map (\s -> s {timestamp = shift (timestamp s)}) samples}
                            }
                }
        }
  where
    o = workoutObservation w
    r = observationRange o
    samples = case observationSport o of
        Cycling c -> motionHeartRate (cyclingMotion c)
        Running v -> motionHeartRate (runningMotion v)
    shift = addUTCTime (fromInteger delta)
