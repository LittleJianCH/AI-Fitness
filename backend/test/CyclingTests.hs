module CyclingTests (cases) where

import qualified Data.Vector as V
import Fixtures
import Workout.Cycling.Empty (emptyCycling)
import qualified Workout.Sport as Sport
import Workout.Types
import Workout.Update (replaceObservation)
import Workout.Validation (validateWorkout)

cases :: [(String, Bool)]
cases =
    [
        ( "cycling baseline accepts independent heart, power, speed, altitude, cadence and route samples"
        , null (validateWorkout workout)
        )
    ,
        ( "cycling observation updates preserve all baseline streams"
        , updatedStreams == Just expectedStreams
        )
    , ("negative cycling speed is rejected", invalidSpeed (-1))
    , ("non-finite cycling power is rejected", invalidPower (1 / 0))
    ]
  where
    streams sport = case sport of
        Cycling c ->
            Just
                ( Sport.heartRate sport
                , Sport.power sport
                , Sport.speed sport
                , Sport.altitude sport
                , cyclingCadence c
                , Sport.position sport
                )
        Running _ -> Nothing
    expectedStreams =
        ( motionHeartRate (cyclingMotion ride)
        , motionPower (cyclingMotion ride)
        , motionSpeed (cyclingMotion ride)
        , motionAltitude (cyclingMotion ride)
        , cyclingCadence ride
        , motionPosition (cyclingMotion ride)
        )
    before = workout {workoutObservation = observation {observationSport = Cycling emptyCycling}}
    updatedStreams = case replaceObservation (WorkoutRevision 1) observation before of
        Right updated -> streams (observationSport (workoutObservation updated))
        Left _ -> Nothing
    invalidMotion motion =
        not . null . validateWorkout $
            workout
                { workoutObservation = observation {observationSport = Cycling ride {cyclingMotion = motion}}
                }
    invalidSpeed x = invalidMotion (cyclingMotion ride) {motionSpeed = V.singleton (Timed start (Speed x))}
    invalidPower x = invalidMotion (cyclingMotion ride) {motionPower = V.singleton (Timed start (Power x))}
