{-# LANGUAGE DeriveGeneric #-}

module Workout.Sport.Types
    ( Sport (..)
    , module Workout.Common.Types
    , module Workout.Cycling.Types
    , module Workout.Running.Types
    ) where

import GHC.Generics (Generic)
import Workout.Common.Types
import Workout.Cycling.Types
import Workout.Running.Types

-- The sum type is the only place that lists the supported sports.
data Sport = Cycling CyclingData | Running RunningData deriving (Eq, Show, Generic)
