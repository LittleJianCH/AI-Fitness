module Storage.Workout.Types (WorkoutFilter (..)) where

import Data.Text (Text)
import Data.Time (UTCTime)

data WorkoutFilter = WorkoutFilter
    { startedFrom :: Maybe UTCTime
    , startedBefore :: Maybe UTCTime
    , sport :: Maybe Text
    , tag :: Maybe Text
    }
