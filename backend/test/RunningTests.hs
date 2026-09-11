module RunningTests (cases) where

import qualified Data.Vector as V
import Fixtures
import Workout.Running.Empty (emptyRunning)
import qualified Workout.Sport as Sport
import Workout.Types
import Workout.Update (replaceObservation)
import Workout.Validation (validateWorkout)

cases :: [(String, Bool)]
cases =
    [
        ( "running baseline accepts independent heart, cadence, altitude and route samples"
        , null (validateWorkout runningWorkout)
        )
    ,
        ( "running observation updates preserve all baseline streams"
        , updatedStreams == Just expectedStreams
        )
    , ("negative running cadence is rejected", invalidCadence [Timed (at 18000) (RunningCadence (-1))])
    ,
        ( "duplicate running cadence timestamps are rejected"
        , invalidCadence [Timed (at 18000) (RunningCadence 160), Timed (at 18000) (RunningCadence 170)]
        )
    ,
        ( "running route coordinates are validated"
        , invalidMotion (runningMotion run) {motionPosition = V.singleton (Timed (at 18000) (Position 91 0))}
        )
    ,
        ( "running altitude samples must fall inside the workout"
        , invalidMotion (runningMotion run) {motionAltitude = V.singleton (Timed start (Altitude 1))}
        )
    ]
  where
    currentObservation = workoutObservation runningWorkout
    streams sport = case sport of
        Running r -> Just (Sport.heartRate sport, runningCadence r, Sport.altitude sport, Sport.position sport)
        Cycling _ -> Nothing
    expectedStreams =
        ( motionHeartRate (runningMotion run)
        , runningCadence run
        , motionAltitude (runningMotion run)
        , motionPosition (runningMotion run)
        )
    before =
        runningWorkout {workoutObservation = currentObservation {observationSport = Running emptyRunning}}
    updatedStreams = case replaceObservation (WorkoutRevision 1) currentObservation before of
        Right updated -> streams (observationSport (workoutObservation updated))
        Left _ -> Nothing
    invalid r =
        not . null . validateWorkout $
            runningWorkout {workoutObservation = currentObservation {observationSport = Running r}}
    invalidMotion motion = invalid run {runningMotion = motion}
    invalidCadence samples = invalid run {runningCadence = V.fromList samples}
