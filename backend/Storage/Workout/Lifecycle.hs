module Storage.Workout.Lifecycle (deleteWorkout) where

import Control.Monad (unless)
import Data.Time (UTCTime)
import qualified Storage.Fit as Fit
import qualified Storage.HealthKit as HealthKit
import Storage.Types (Store)
import Storage.User.Types (UserId)
import qualified Storage.Workout.Submission as Manual
import Workout.Types (WorkoutId, WorkoutRevision)

-- Runs inside the owner's account-locked transaction. Source adapters only
-- suppress their own records; this coordinator preserves the source lock order.
deleteWorkout :: UserId -> WorkoutId -> WorkoutRevision -> UTCTime -> Store ()
deleteWorkout uid wid expected now = do
    fit <- Fit.deleteWorkout uid wid expected now
    unless fit $ do
        healthKit <- HealthKit.deleteWorkout uid wid expected now
        unless healthKit (Manual.deleteManual uid wid expected)
