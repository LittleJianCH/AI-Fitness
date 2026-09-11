module Workout.Validation.Types
    ( ValidationError (..)
    , UpdateError (..)
    ) where

import Data.Text (Text)
import qualified Workout.Identity.Types

data ValidationError = ValidationError
    { errorField :: Text
    , errorMessage :: Text
    }
    deriving (Eq, Show)

-- Conflicts are explicit; callers must not overwrite a concurrently edited record.
data UpdateError
    = RevisionConflict Workout.Identity.Types.WorkoutRevision Workout.Identity.Types.WorkoutRevision
    | InvalidWorkout [ValidationError]
    deriving (Eq, Show)
