{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.Workout.Codec () where

import Api.Codec (ViaJSON (..))
import Api.Workout.Cycling.Codec ()
import Api.Workout.Running.Codec ()
import Control.Lens (traversed, (%~), (&), _Just)
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema (..), oneOf, required, schema, _Inline)
import Data.Proxy (Proxy (..))
import Workout.Types

deriving via (ViaJSON Workout) instance ToJSON Workout
deriving via (ViaJSON Workout) instance FromJSON Workout
deriving via (ViaJSON Workout) instance ToSchema Workout

deriving via (ViaJSON WorkoutObservation) instance ToJSON WorkoutObservation
deriving via (ViaJSON WorkoutObservation) instance FromJSON WorkoutObservation
deriving via (ViaJSON WorkoutObservation) instance ToSchema WorkoutObservation

deriving via (ViaJSON WorkoutUserData) instance ToJSON WorkoutUserData
deriving via (ViaJSON WorkoutUserData) instance FromJSON WorkoutUserData
deriving via (ViaJSON WorkoutUserData) instance ToSchema WorkoutUserData

deriving via (ViaJSON WorkoutGroup) instance ToJSON WorkoutGroup
deriving via (ViaJSON WorkoutGroup) instance FromJSON WorkoutGroup
deriving via (ViaJSON WorkoutGroup) instance ToSchema WorkoutGroup

deriving via (ViaJSON AthleteContext) instance ToJSON AthleteContext
deriving via (ViaJSON AthleteContext) instance FromJSON AthleteContext
deriving via (ViaJSON AthleteContext) instance ToSchema AthleteContext

deriving via (ViaJSON WorkoutEvent) instance ToJSON WorkoutEvent
deriving via (ViaJSON WorkoutEvent) instance FromJSON WorkoutEvent

-- openapi3 marks a unary record payload as required even when its field is
-- Maybe. Correct that library special case on the derived schema, keeping the
-- canonical record and the JSON codec authoritative.
instance ToSchema WorkoutEvent where
    declareNamedSchema _ =
        ( \value ->
            value
                & schema . oneOf . _Just . traversed . _Inline . required
                    %~ filter (`notElem` ["markerLabel", "reminderDuration", "batteryDevice"])
        )
            <$> declareNamedSchema (Proxy :: Proxy (ViaJSON WorkoutEvent))

deriving via (ViaJSON CoursePoint) instance ToJSON CoursePoint
deriving via (ViaJSON CoursePoint) instance FromJSON CoursePoint
deriving via (ViaJSON CoursePoint) instance ToSchema CoursePoint

deriving via (ViaJSON CoursePointKind) instance ToJSON CoursePointKind
deriving via (ViaJSON CoursePointKind) instance FromJSON CoursePointKind
deriving via (ViaJSON CoursePointKind) instance ToSchema CoursePointKind

deriving via (ViaJSON DataIssue) instance ToJSON DataIssue
deriving via (ViaJSON DataIssue) instance FromJSON DataIssue
deriving via (ViaJSON DataIssue) instance ToSchema DataIssue

deriving via (ViaJSON StatisticsInclusion) instance ToJSON StatisticsInclusion
deriving via (ViaJSON StatisticsInclusion) instance FromJSON StatisticsInclusion
deriving via (ViaJSON StatisticsInclusion) instance ToSchema StatisticsInclusion

deriving via (ViaJSON Sport) instance ToJSON Sport
deriving via (ViaJSON Sport) instance FromJSON Sport
deriving via (ViaJSON Sport) instance ToSchema Sport
