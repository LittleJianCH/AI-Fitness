module Workout.Update
    ( replaceObservation
    , replaceUserData
    , UpdateError (..)
    ) where

import qualified Workout.Sport as Sport
import Workout.Types
import Workout.Validation (validateWorkout)
import Workout.Validation.Types (UpdateError (..))

-- Call only for the existing workout resolved by the import index, never by a
-- timestamp match. The database must still perform compare-and-swap on revision.
replaceObservation :: WorkoutRevision -> WorkoutObservation -> Workout -> Either UpdateError Workout
replaceObservation expected observation current =
    update
        expected
        (current {workoutObservation = observation})
        current

replaceUserData :: WorkoutRevision -> WorkoutUserData -> Workout -> Either UpdateError Workout
replaceUserData expected userData current =
    update
        expected
        (current {workoutUserData = userData})
        current

update :: WorkoutRevision -> Workout -> Workout -> Either UpdateError Workout
update expected candidate current
    | expected /= workoutRevision current = Left (RevisionConflict expected (workoutRevision current))
    | otherwise = case validateWorkout next of
        [] -> Right next
        errors -> Left (InvalidWorkout errors)
  where
    WorkoutRevision revision = workoutRevision current
    next =
        candidate
            { workoutRevision = WorkoutRevision (revision + 1)
            , workoutObservation = invalidate (workoutObservation candidate)
            }

-- Coarse invalidation is deliberate for v1. Reported values survive untouched.
invalidate :: WorkoutObservation -> WorkoutObservation
invalidate o = o {observationSport = Sport.invalidateCalculated (observationSport o)}
