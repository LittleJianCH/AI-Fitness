-- Convenience exports; sport-specific implementations live with each sport.
module Workout.Empty
    ( emptyAthlete
    , emptyUserData
    , module Workout.Common.Empty
    , module Workout.Cycling.Empty
    , module Workout.Running.Empty
    , emptyStatistics
    , reportedOnly
    ) where

import qualified Data.Vector as V
import Workout.Common.Empty
import Workout.Cycling.Empty
import Workout.Measurement.Summary (emptyStatistics, reportedOnly)
import Workout.Running.Empty
import Workout.Types

emptyAthlete :: AthleteContext
emptyAthlete = AthleteContext Nothing Nothing Nothing

emptyUserData :: WorkoutUserData
emptyUserData = WorkoutUserData Nothing Nothing V.empty IncludeInStatistics
