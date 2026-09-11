{-# LANGUAGE OverloadedStrings #-}

module ImportOutputTests (cases) where

import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.UUID.Types as UUID
import Fixtures
import Import.Output
import Import.State
import Import.Types
import Workout.Types
import Workout.Update (UpdateError (..))
import Workout.Validation (validateWorkout)

cases :: [(String, Bool)]
cases =
    [
        ( "native multisport output links independent valid workouts"
        , null (validateWorkout runningWorkout) && null (validateImportOutput groupedOutput)
        )
    ,
        ( "single-sport output does not create a group"
        , refreshOutput singleOutput (rideCandidate :| []) (workout :| []) Nothing
            == Right (updatedRide :| [], Nothing)
        )
    ,
        ( "repeated multisport input returns every ID and its group"
        , planImport NormalImport groupedRecord == ReturnExisting groupedOutput
        )
    ,
        ( "failed multisport refresh retains all prior IDs"
        , planImport NormalImport (recordFailure (at 2) "failed" groupedRecord)
            == ReturnExisting groupedOutput
        )
    ,
        ( "batch refresh matches part identities despite reordered inputs and preserves user order"
        , refreshOutput
            groupedOutput
            (runCandidate :| [rideCandidate])
            (runningWorkout :| [workout])
            (Just reorderedGroup)
            == Right (updatedRide :| [updatedRun], Just reorderedGroup)
        )
    ,
        ( "missing parsed part needs reconciliation"
        , refresh (rideCandidate :| []) == Left OutputPartsChanged
        )
    ,
        ( "additional parsed part needs reconciliation"
        , refresh (rideCandidate :| [runCandidate, runCandidate {refreshPartKey = ImportPartKey "extra"}])
            == Left OutputPartsChanged
        )
    ,
        ( "duplicate parsed part cannot replace a missing part"
        , refresh (rideCandidate :| [rideCandidate]) == Left OutputPartsChanged
        )
    ,
        ( "wrong stored members prevent refresh"
        , refreshOutput groupedOutput candidates (workout :| [workout]) (Just group)
            == Left StoredOutputMismatch
        )
    ,
        ( "missing source group prevents refresh"
        , refreshOutput groupedOutput candidates stored Nothing == Left StoredOutputMismatch
        )
    ,
        ( "changed group membership needs reconciliation"
        , refreshOutput groupedOutput candidates stored (Just group {workoutGroupMembers = wid :| []})
            == Left StoredOutputMismatch
        )
    ,
        ( "one revision conflict rejects entire batch"
        , case refresh (rideCandidate :| [runCandidate {refreshExpectedRevision = WorkoutRevision 0}]) of
            Left (WorkoutRefreshFailed ident (RevisionConflict _ _)) -> ident == otherId
            _ -> False
        )
    ,
        ( "one invalid observation rejects entire batch"
        , case refresh
            ( rideCandidate
                :| [ runCandidate
                        { refreshObservation = (workoutObservation runningWorkout) {observationRange = TimeRange start start}
                        }
                   ]
            ) of
            Left (WorkoutRefreshFailed ident (InvalidWorkout _)) -> ident == otherId
            _ -> False
        )
    ,
        ( "grouped import requires multiple workouts"
        , validateGroupOutput (ImportedWorkout ridePart wid :| []) == [TooFewGroupedWorkouts]
        )
    ,
        ( "imported part identities must be distinct"
        , validateGroupOutput (ImportedWorkout ridePart wid :| [ImportedWorkout ridePart otherId])
            == [DuplicateOutputPartKeys]
        )
    ,
        ( "imported workout identities must be distinct"
        , validateGroupOutput (ImportedWorkout ridePart wid :| [ImportedWorkout runPart wid])
            == [DuplicateOutputWorkoutIds]
        )
    ,
        ( "blank part keys cannot be published"
        , validateImportOutput (SingleWorkout (ImportedWorkout (ImportPartKey " ") wid))
            == [BlankOutputPartKey]
        )
    ,
        ( "invalid output mapping prevents refresh"
        , case refreshOutput
            (SingleWorkout (ImportedWorkout (ImportPartKey " ") wid))
            (rideCandidate :| [])
            (workout :| [])
            Nothing of
            Left (InvalidImportOutput _) -> True
            _ -> False
        )
    ,
        ( "output validation retains error accumulation order"
        , validateImportOutput
            ( GroupedWorkouts
                (WorkoutGroupId UUID.nil)
                (ImportedWorkout (ImportPartKey " ") (WorkoutId UUID.nil) :| [])
            )
            == [BlankOutputPartKey, NilOutputWorkoutId, NilOutputGroupId, TooFewGroupedWorkouts]
        )
    ,
        ( "invalid output takes precedence over mismatched candidates"
        , refreshOutput
            (SingleWorkout (ImportedWorkout (ImportPartKey " ") wid))
            (runCandidate :| [])
            stored
            Nothing
            == Left (InvalidImportOutput [BlankOutputPartKey])
        )
    ]
  where
    validateGroupOutput = validateImportOutput . GroupedWorkouts (workoutGroupId group)
    rideCandidate = RefreshCandidate ridePart (WorkoutRevision 1) observation
    runCandidate = RefreshCandidate runPart (WorkoutRevision 1) (workoutObservation runningWorkout)
    candidates = rideCandidate :| [runCandidate]
    stored = workout :| [runningWorkout]
    updatedRide = workout {workoutRevision = WorkoutRevision 2}
    updatedRun = runningWorkout {workoutRevision = WorkoutRevision 2}
    reorderedGroup =
        group
            { workoutGroupTitle = "My brick"
            , workoutGroupNotes = Just "Keep group notes"
            , workoutGroupMembers = otherId :| [wid]
            }
    refresh cs = refreshOutput groupedOutput cs stored (Just group)
    groupedRecord =
        importRecord
            { lastSuccessfulImport = Just (ImportSuccess groupedOutput (ImportVersion "normalize-v1") start)
            }
