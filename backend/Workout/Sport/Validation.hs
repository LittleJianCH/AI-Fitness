module Workout.Sport.Validation (sportErrors, sportRevisionErrors) where

import qualified Workout.Cycling.Validation as Cycling
import Workout.Identity.Types (WorkoutRevision)
import Workout.Measurement.Types (TimeRange)
import qualified Workout.Running.Validation as Running
import Workout.Sport.Types (Sport (..))
import Workout.Validation.Types (ValidationError)

sportErrors :: TimeRange -> Sport -> [ValidationError]
sportErrors r sport = case sport of
    Cycling dat -> Cycling.validateCycling r dat
    Running dat -> Running.validateRunning r dat

sportRevisionErrors :: WorkoutRevision -> Sport -> [ValidationError]
sportRevisionErrors revision sport = case sport of
    Cycling dat -> Cycling.validateCyclingRevision revision dat
    Running dat -> Running.validateRunningRevision revision dat
