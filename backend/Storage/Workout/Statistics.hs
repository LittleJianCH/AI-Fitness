{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.Workout.Statistics (load, create, replaceUserData, replaceObservation) where

import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (throwE)
import Data.Aeson (toJSON)
import Data.Coerce (coerce)
import Data.Time (UTCTime)
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import Storage.Codec (jsonErrors)
import Storage.Types
import Storage.User.Types (UserId (..))
import qualified Storage.Workout as Workouts
import qualified Workout.Statistics as Statistics
import Workout.Types
import qualified Workout.Update as Update
import qualified Workout.Validation as Validation

-- Called inside the authenticated owner's account-locked transaction. Persisting
-- a derived cache does not change the input revision or the source observation.
load :: UTCTime -> UserId -> WorkoutId -> Store Workout
load now uid wid = do
    workout <- Workouts.loadWorkout uid wid >>= maybe (throwE WorkoutNotFound) pure
    if Statistics.isCurrent workout then pure workout else save now uid workout

-- Calculate against the final input revision before the single canonical write.
-- Incoming calculated summaries are never trusted.
create :: UTCTime -> UserId -> Workout -> Store Workout
create now uid original = do
    let errors =
            Validation.validateWorkout original
                <> jsonErrors "observation" (toJSON (workoutObservation original))
                <> jsonErrors "userData" (toJSON (workoutUserData original))
    unless (null errors) (throwE (InvalidWorkout errors))
    let workout = Statistics.calculate now original
    Workouts.createWorkout uid workout
    pure workout

replaceUserData
    :: UTCTime -> UserId -> WorkoutId -> WorkoutRevision -> WorkoutUserData -> Store Workout
replaceUserData now uid wid expected userData =
    Workouts.updateWorkout
        uid
        wid
        expected
        (fmap (Statistics.calculate now) . Update.replaceUserData expected userData)

-- Import reconciliation has already loaded and checked this workout under the
-- account lock. Reuse it; SQL still compares the expected revision at the write.
replaceObservation
    :: UTCTime -> UserId -> Workout -> WorkoutRevision -> WorkoutObservation -> Store Workout
replaceObservation now uid current expected observation =
    case Update.replaceObservation expected observation current of
        Left (Update.RevisionConflict _ _) -> throwE WorkoutConflict
        Left (Update.InvalidWorkout errors) -> throwE (InvalidWorkout errors)
        Right next -> Workouts.saveUpdated uid expected (Statistics.calculate now next)

save :: UTCTime -> UserId -> Workout -> Store Workout
save now uid original = do
    let workout = Statistics.calculate now original
        errors = Validation.validateWorkout workout
    unless (null errors) (throwE (InvalidWorkout errors))
    count <-
        lift $
            T.statement
                ( coerce uid
                , coerce (workoutId workout)
                , Workouts.revisionText (workoutRevision workout)
                , toJSON (workoutObservation workout)
                )
                [TH.rowsAffectedStatement|
            UPDATE workouts SET observation = $4 :: jsonb
            WHERE user_id = $1 :: uuid AND id = $2 :: uuid AND revision = ($3 :: text) :: numeric
        |]
    unless (count == 1) (throwE WorkoutConflict)
    pure workout
