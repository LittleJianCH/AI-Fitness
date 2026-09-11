{-# LANGUAGE OverloadedStrings #-}

module ContractFixtures (workout, runningWorkout, workoutPage, failure, exportBundle) where

import Api.Common.Types
import qualified Api.Export.Types as Export
import qualified Api.Workout.Types as API
import Data.Time (addUTCTime)
import qualified Data.Vector as Vector
import qualified Fixtures as F
import Workout.Types

-- Reuse the synthetic domain fixtures so the contract must preserve their actual
-- canonical fields. This revision deliberately exceeds JavaScript's exact range.
workout :: Workout
workout =
    F.workout
        { workoutRevision = WorkoutRevision 9007199254740993
        , workoutUserData = (workoutUserData F.workout) {workoutNotes = Nothing}
        , workoutObservation =
            F.observation
                { observationEvents =
                    observationEvents F.observation
                        Vector.++ Vector.fromList
                            [Timed (F.at 17442) (OtherEvent "example" Nothing), Timed (F.at 17442) (LowBattery Nothing)]
                , observationExtensions =
                    observationExtensions F.observation
                        Vector.++ Vector.fromList
                            [ ExtensionField "example.text" "Example text" (TextExtension Vector.empty Nothing)
                            , ExtensionField "example.boolean" "Example flag" (BooleanExtension Vector.empty (Just False))
                            ]
                }
        }

runningWorkout :: Workout
runningWorkout = F.runningWorkout {workoutRevision = WorkoutRevision 9007199254740993}

workoutPage :: Page API.WorkoutCard
workoutPage = Page (Vector.fromList (card <$> [workout, runningWorkout])) Nothing
  where
    card w =
        API.WorkoutCard
            (workoutId w)
            (workoutRevision w)
            (observationRange (workoutObservation w))
            (workoutUserData w)
            ( case observationSport (workoutObservation w) of
                Cycling c -> API.CyclingSummary (cyclingSummary c)
                Running r -> API.RunningSummary (runningSummary r)
            )

failure :: Problem
failure =
    Problem
        "invalid_query"
        "Invalid page size"
        "contract-fixture"
        [FieldError "/limit" "out_of_range" "Expected a limit between 1 and 100"]

exportBundle :: Export.CanonicalExport
exportBundle =
    Export.CanonicalExport
        Export.CanonicalV1
        (Timestamp (addUTCTime 0.125 F.start))
        [workout, runningWorkout]
        [F.group]
