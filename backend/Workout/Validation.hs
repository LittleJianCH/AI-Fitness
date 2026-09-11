{-# LANGUAGE OverloadedStrings #-}

module Workout.Validation
    ( validateWorkout
    , validateObservation
    , validateGroup
    , validateTimeSeries
    , ValidationError (..)
    ) where

import Data.List (nub)
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T
import qualified Data.UUID.Types as UUID
import qualified Data.Vector as V
import Workout.Measurement.Validation
import Workout.Sport.Validation (sportErrors, sportRevisionErrors)
import Workout.Types
import Workout.Validation.Types

workoutEventErrors :: WorkoutEvent -> [ValidationError]
workoutEventErrors event = case event of
    TimeReminder d -> optional "duration" d
    OtherEvent kind _ -> check "kind" "Event kind is required" (not (T.null (T.strip kind)))
    _ -> []

validateObservation :: WorkoutObservation -> [ValidationError]
validateObservation o =
    concat
        [ rangeErrors "range" r
        , prefix "sport" (sportErrors r (observationSport o))
        , events "events" r workoutEventErrors (observationEvents o)
        , concat (V.toList (V.imap course (observationCoursePoints o)))
        , optional "athlete.height" (athleteHeight athlete)
        , check
            "athlete.height"
            "Height must be positive"
            (maybe True (\(Distance x) -> positive x) (athleteHeight athlete))
        , optional "athlete.mass" (athleteMass athlete)
        , optional "athlete.thresholdPower" (thresholdPower athlete)
        , check
            "athlete.thresholdPower"
            "Threshold power must be positive"
            (maybe True (\(Power x) -> positive x) (thresholdPower athlete))
        , extensions r (observationExtensions o)
        , concatMap issue (V.toList (observationDataIssues o))
        ]
  where
    r = observationRange o
    athlete = observationAthlete o
    course i p =
        prefix ("coursePoints." <> T.pack (show i)) $
            check "position" "Invalid position" (validValue (coursePointPosition p))
                ++ check "time" "Course point time outside workout" (maybe True (inside r) (coursePointTime p))
    issue x =
        check "dataIssue.field" "Issue field is required" (not (T.null (T.strip (issueField x))))
            ++ check
                "dataIssue.description"
                "Issue description is required"
                (not (T.null (T.strip (issueDescription x))))
            ++ maybe
                []
                ( \ir ->
                    rangeErrors "dataIssue.range" ir
                        ++ check
                            "dataIssue.range"
                            "Issue range outside workout"
                            (inside r (rangeStart ir) && inside r (rangeEnd ir))
                )
                (issueRange x)

validateWorkout :: Workout -> [ValidationError]
validateWorkout w =
    check "id" "Workout ID must not be nil" (wid /= UUID.nil)
        ++ check "revision" "Revision must be positive" (revision > 0)
        ++ validateObservation (workoutObservation w)
        ++ revisionErrors (workoutRevision w) (workoutObservation w)
  where
    WorkoutId wid = workoutId w
    WorkoutRevision revision = workoutRevision w

revisionErrors :: WorkoutRevision -> WorkoutObservation -> [ValidationError]
revisionErrors revision = sportRevisionErrors revision . observationSport

validateGroup :: WorkoutGroup -> [ValidationError]
validateGroup group =
    check "id" "Group ID must not be nil" (gid /= UUID.nil)
        ++ check "title" "Group title is required" (not (T.null (T.strip (workoutGroupTitle group))))
        ++ check "members" "Group members must be unique" (length members == length (nub members))
        ++ check "members" "Member IDs must not be nil" (all (\(WorkoutId x) -> x /= UUID.nil) members)
  where
    WorkoutGroupId gid = workoutGroupId group
    members = NE.toList (workoutGroupMembers group)
