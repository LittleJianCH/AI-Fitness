{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.Workout.AnalysisCodec () where

import Api.Codec (ViaJSON (..))
import Api.Settings.Codec ()
import Api.Workout.Identity.Codec ()
import Api.Workout.Measurement.Codec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Workout.Analysis.Types

deriving via ViaJSON HeartAnalysis instance ToJSON HeartAnalysis
deriving via ViaJSON HeartAnalysis instance FromJSON HeartAnalysis
deriving via ViaJSON HeartAnalysis instance ToSchema HeartAnalysis
deriving via ViaJSON HeartLoadStatus instance ToJSON HeartLoadStatus
deriving via ViaJSON HeartLoadStatus instance FromJSON HeartLoadStatus
deriving via ViaJSON HeartLoadStatus instance ToSchema HeartLoadStatus
deriving via ViaJSON ZoneDuration instance ToJSON ZoneDuration
deriving via ViaJSON ZoneDuration instance FromJSON ZoneDuration
deriving via ViaJSON ZoneDuration instance ToSchema ZoneDuration

deriving via (ViaJSON WorkoutAnalysis) instance ToJSON WorkoutAnalysis
deriving via (ViaJSON WorkoutAnalysis) instance FromJSON WorkoutAnalysis
deriving via (ViaJSON WorkoutAnalysis) instance ToSchema WorkoutAnalysis
deriving via (ViaJSON MetricKind) instance ToJSON MetricKind
deriving via (ViaJSON MetricKind) instance FromJSON MetricKind
deriving via (ViaJSON MetricKind) instance ToSchema MetricKind
deriving via (ViaJSON MetricAnalysis) instance ToJSON MetricAnalysis
deriving via (ViaJSON MetricAnalysis) instance FromJSON MetricAnalysis
deriving via (ViaJSON MetricAnalysis) instance ToSchema MetricAnalysis
deriving via (ViaJSON DistributionBin) instance ToJSON DistributionBin
deriving via (ViaJSON DistributionBin) instance FromJSON DistributionBin
deriving via (ViaJSON DistributionBin) instance ToSchema DistributionBin
deriving via (ViaJSON PowerAnalysis) instance ToJSON PowerAnalysis
deriving via (ViaJSON PowerAnalysis) instance FromJSON PowerAnalysis
deriving via (ViaJSON PowerAnalysis) instance ToSchema PowerAnalysis
deriving via (ViaJSON RunningAnalysis) instance ToJSON RunningAnalysis
deriving via (ViaJSON RunningAnalysis) instance FromJSON RunningAnalysis
deriving via (ViaJSON RunningAnalysis) instance ToSchema RunningAnalysis
deriving via (ViaJSON SplitSet) instance ToJSON SplitSet
deriving via (ViaJSON SplitSet) instance FromJSON SplitSet
deriving via (ViaJSON SplitSet) instance ToSchema SplitSet
deriving via (ViaJSON DistanceSplit) instance ToJSON DistanceSplit
deriving via (ViaJSON DistanceSplit) instance FromJSON DistanceSplit
deriving via (ViaJSON DistanceSplit) instance ToSchema DistanceSplit
deriving via (ViaJSON SplitComparison) instance ToJSON SplitComparison
deriving via (ViaJSON SplitComparison) instance FromJSON SplitComparison
deriving via (ViaJSON SplitComparison) instance ToSchema SplitComparison
deriving via (ViaJSON MetricRelationship) instance ToJSON MetricRelationship
deriving via (ViaJSON MetricRelationship) instance FromJSON MetricRelationship
deriving via (ViaJSON MetricRelationship) instance ToSchema MetricRelationship
deriving via (ViaJSON RelationshipPoint) instance ToJSON RelationshipPoint
deriving via (ViaJSON RelationshipPoint) instance FromJSON RelationshipPoint
deriving via (ViaJSON RelationshipPoint) instance ToSchema RelationshipPoint
