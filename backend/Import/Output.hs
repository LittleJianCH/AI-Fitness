{-# LANGUAGE TupleSections #-}

module Import.Output (outputWorkouts, validateImportOutput, refreshOutput) where

import Data.Bifunctor (first)
import Data.List (find, nub, sort)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T
import qualified Data.UUID.Types as UUID
import Import.Types
import Workout.Types
import Workout.Update (replaceObservation)
import Workout.Validation (validateGroup)

outputWorkouts :: ImportOutput -> NonEmpty ImportedWorkout
outputWorkouts output = case output of
    SingleWorkout member -> member :| []
    GroupedWorkouts _ members -> members

validateImportOutput :: ImportOutput -> [ImportOutputError]
validateImportOutput output =
    [DuplicateOutputPartKeys | length keys /= length (nub keys)]
        ++ [DuplicateOutputWorkoutIds | length ids /= length (nub ids)]
        ++ [BlankOutputPartKey | any (\(ImportPartKey k) -> T.null (T.strip k)) keys]
        ++ [NilOutputWorkoutId | any (\(WorkoutId x) -> x == UUID.nil) ids]
        ++ case output of
            SingleWorkout _ -> []
            GroupedWorkouts (WorkoutGroupId gid) _ ->
                [NilOutputGroupId | gid == UUID.nil]
                    ++ [TooFewGroupedWorkouts | length ids < 2]
  where
    members = NE.toList (outputWorkouts output)
    keys = importedPartKey <$> members
    ids = importedWorkoutId <$> members

-- Prepare an all-or-nothing replacement for one already successful input.
-- Match by source-local identity, never incoming position, sport or time.
-- Existing group title, notes and user-defined member order are preserved.
-- A changed part set needs explicit reconciliation, not automatic ID reassignment.
-- The application must commit all values and the import success record in one
-- transaction, with revision checks repeated at the database write boundary.
refreshOutput
    :: ImportOutput
    -> NonEmpty RefreshCandidate
    -> NonEmpty Workout
    -> Maybe WorkoutGroup
    -> Either RefreshError (NonEmpty Workout, Maybe WorkoutGroup)
refreshOutput output candidates stored group
    | errors@(_ : _) <- validateImportOutput output = Left (InvalidImportOutput errors)
    | sort candidateKeys /= sort expectedKeys = Left OutputPartsChanged
    | sort storedIds /= sort expectedIds = Left StoredOutputMismatch
    | not groupMatches = Left StoredOutputMismatch
    | otherwise = (,group) <$> traverse refresh (outputWorkouts output)
  where
    members = NE.toList (outputWorkouts output)
    expectedKeys = importedPartKey <$> members
    expectedIds = importedWorkoutId <$> members
    candidateKeys = refreshPartKey <$> NE.toList candidates
    storedIds = workoutId <$> NE.toList stored
    groupMatches = case (output, group) of
        (SingleWorkout _, Nothing) -> True
        (GroupedWorkouts gid _, Just g) ->
            workoutGroupId g == gid
                && null (validateGroup g)
                && sort (NE.toList (workoutGroupMembers g)) == sort expectedIds
        _ -> False
    refresh member = case ( find ((== importedPartKey member) . refreshPartKey) (NE.toList candidates)
                          , find ((== importedWorkoutId member) . workoutId) (NE.toList stored)
                          ) of
        (Just candidate, Just current) ->
            first (WorkoutRefreshFailed (workoutId current)) $
                replaceObservation
                    (refreshExpectedRevision candidate)
                    (refreshObservation candidate)
                    current
        _ -> Left StoredOutputMismatch
