module Workout.Identity.Types
    ( WorkoutId (..)
    , WorkoutGroupId (..)
    , WorkoutRevision (..)
    ) where

import Data.UUID.Types (UUID)

newtype WorkoutId = WorkoutId UUID deriving (Eq, Ord, Show)
newtype WorkoutGroupId = WorkoutGroupId UUID deriving (Eq, Ord, Show)
newtype WorkoutRevision = WorkoutRevision Integer deriving (Eq, Ord, Show)
