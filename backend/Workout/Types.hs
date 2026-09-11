{-# LANGUAGE DeriveGeneric #-}

module Workout.Types
    ( module Workout.Identity.Types
    , module Workout.Measurement.Types
    , module Workout.Sport.Types
    , Workout (..)
    , WorkoutObservation (..)
    , WorkoutUserData (..)
    , StatisticsInclusion (..)
    , WorkoutGroup (..)
    , AthleteContext (..)
    , WorkoutEvent (..)
    , CoursePoint (..)
    , CoursePointKind (..)
    , DataIssue (..)
    ) where

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Vector (Vector)
import GHC.Generics (Generic)
import Workout.Identity.Types
import Workout.Measurement.Types
import Workout.Sport.Types

data Workout = Workout
    { workoutId :: WorkoutId
    , workoutRevision :: WorkoutRevision
    , workoutObservation :: WorkoutObservation
    , workoutUserData :: WorkoutUserData
    }
    deriving (Eq, Show, Generic)

-- Import owns these normalized observations for exactly one sport. A source
-- containing several sports produces separate workouts linked by a WorkoutGroup.
data WorkoutObservation = WorkoutObservation
    { observationRange :: TimeRange
    , observationSport :: Sport
    , observationEvents :: Vector (Timed WorkoutEvent)
    , observationCoursePoints :: Vector CoursePoint
    , observationAthlete :: AthleteContext
    , observationExtensions :: Vector ExtensionField
    , observationDataIssues :: Vector DataIssue
    }
    deriving (Eq, Show, Generic)

-- Editable fields survive re-import. Arbitrary edits to observations are not
-- supported until a field ownership policy exists for those edits.
data WorkoutUserData = WorkoutUserData
    { workoutTitle :: Maybe Text
    , workoutNotes :: Maybe Text
    , workoutTags :: Vector Text
    , statisticsInclusion :: StatisticsInclusion
    }
    deriving (Eq, Show, Generic)

data StatisticsInclusion = IncludeInStatistics | ExcludeFromStatistics
    deriving (Eq, Show, Generic)

-- Membership order is user-defined. No time continuity or exclusive membership
-- is required; duplicate members within one group are rejected by validation.
data WorkoutGroup = WorkoutGroup
    { workoutGroupId :: WorkoutGroupId
    , workoutGroupTitle :: Text
    , workoutGroupNotes :: Maybe Text
    , workoutGroupMembers :: NonEmpty WorkoutId
    }
    deriving (Eq, Show, Generic)

data AthleteContext = AthleteContext
    { athleteHeight :: Maybe Distance
    , athleteMass :: Maybe Mass
    , thresholdPower :: Maybe Power
    }
    deriving (Eq, Show, Generic)

data WorkoutEvent
    = TimerStarted
    | TimerStopped
    | UserMarker {markerLabel :: Maybe Text}
    | TimeReminder {reminderDuration :: Maybe Duration}
    | LowBattery {batteryDevice :: Maybe Text}
    | OtherEvent {eventName :: Text, eventDetail :: Maybe Text}
    deriving (Eq, Show, Generic)

data CoursePoint = CoursePoint
    { coursePointName :: Maybe Text
    , coursePointPosition :: Position
    , coursePointTime :: Maybe UTCTime
    , coursePointKind :: CoursePointKind
    }
    deriving (Eq, Show, Generic)

data CoursePointKind = RouteStart | RouteEnd | Waypoint | OtherCoursePoint Text
    deriving (Eq, Show, Generic)

-- Canonical field paths and an optional affected range, not sample provenance.
data DataIssue = DataIssue
    { issueField :: Text
    , issueRange :: Maybe TimeRange
    , issueDescription :: Text
    }
    deriving (Eq, Show, Generic)
