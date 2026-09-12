{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.Workout.Statistics (load, refresh) where

import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (throwE)
import Data.Aeson (toJSON)
import Data.Coerce (coerce)
import Data.Time (UTCTime)
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import Storage.Types
import Storage.User.Types (UserId (..))
import qualified Storage.Workout as Workouts
import qualified Workout.Statistics as Statistics
import Workout.Types
import qualified Workout.Validation as Validation

-- Called inside the authenticated owner's account-locked transaction. Persisting
-- a derived cache does not change the input revision or the source observation.
load :: UTCTime -> UserId -> WorkoutId -> Store Workout
load now uid wid = do
    workout <- Workouts.loadWorkout uid wid >>= maybe (throwE WorkoutNotFound) pure
    if Statistics.isCurrent workout then pure workout else save now uid workout

-- Writes always recompute: a client-supplied calculated result is not trusted.
refresh :: UTCTime -> UserId -> WorkoutId -> Store Workout
refresh now uid wid = Workouts.loadWorkout uid wid >>= maybe (throwE WorkoutNotFound) (save now uid)

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
