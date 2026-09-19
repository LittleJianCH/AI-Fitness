{-# LANGUAGE DeriveGeneric #-}

module Workout.Analysis.Types
    ( WorkoutAnalysis (..)
    , MetricKind (..)
    , MetricAnalysis (..)
    , DistributionBin (..)
    , PowerAnalysis (..)
    , RunningAnalysis (..)
    , SplitSet (..)
    , DistanceSplit (..)
    , SplitComparison (..)
    , MetricRelationship (..)
    , RelationshipPoint (..)
    , HeartAnalysis (..)
    , HeartLoadStatus (..)
    , ZoneDuration (..)
    ) where

import Data.Text (Text)
import Data.Vector (Vector)
import GHC.Generics (Generic)
import Profile.Types (BodyProfile, SettingsRevision)
import Workout.Identity.Types (WorkoutId, WorkoutRevision)
import Workout.Measurement.Types (Statistics)

-- This is a read projection, not stored observations or a replacement summary.
-- All numeric values use canonical units. Percentages use percentage points.
data WorkoutAnalysis = WorkoutAnalysis
    { analysisWorkoutId :: WorkoutId
    , analysisRevision :: WorkoutRevision
    , analysisMethod :: Text
    , analysisMaxGapSeconds :: Int
    , analysisSettingsRevision :: SettingsRevision
    , analysisBodyProfile :: Maybe BodyProfile
    , analysisHeart :: HeartAnalysis
    , analysisPowerZones :: Vector ZoneDuration
    , analysisMetrics :: Vector MetricAnalysis
    , analysisPower :: PowerAnalysis
    , analysisRunning :: Maybe RunningAnalysis
    , analysisSplits :: Vector SplitSet
    , analysisHalves :: Maybe SplitComparison
    , analysisRelationships :: Vector MetricRelationship
    , analysisNotes :: Vector Text
    }
    deriving (Eq, Show, Generic)

data HeartLoadStatus
    = HeartLoadAvailable
    | HeartProfileMissing
    | HeartCoverageInsufficient
    | HeartNoActiveTime
    | HeartExcluded
    | HeartCalculationUnavailable
    deriving (Eq, Show, Generic)

data HeartAnalysis = HeartAnalysis
    { heartLoadStatus :: HeartLoadStatus
    , heartHrss :: Maybe Double
    , heartTrimp :: Maybe Double
    , heartActiveSeconds :: Maybe Double
    , heartCoveredSeconds :: Maybe Double
    , heartCoverageFraction :: Maybe Double
    , heartUsesRecordedTimer :: Bool
    , heartZones :: Vector ZoneDuration
    }
    deriving (Eq, Show, Generic)

data ZoneDuration = ZoneDuration
    { zoneIndex :: Int
    , zoneLower :: Double
    , zoneUpper :: Maybe Double
    , zoneSeconds :: Double
    }
    deriving (Eq, Show, Generic)

data MetricKind
    = HeartRateMetric
    | PowerMetric
    | SpeedMetric
    | CadenceMetric
    | AltitudeMetric
    | StepLengthMetric
    | VerticalOscillationMetric
    | GroundContactTimeMetric
    | TemperatureMetric
    | GradeMetric
    deriving (Eq, Ord, Show, Generic)

data MetricAnalysis = MetricAnalysis
    { metricKind :: MetricKind
    , metricStatistics :: Statistics Double
    , metricSampleCount :: Int
    , metricCoveredSeconds :: Double
    , metricAverageExcludingZeros :: Maybe Double
    , metricDistribution :: Vector DistributionBin
    }
    deriving (Eq, Show, Generic)

data DistributionBin = DistributionBin
    { binLower :: Double
    , binUpper :: Double
    , binSeconds :: Double
    }
    deriving (Eq, Show, Generic)

data PowerAnalysis = PowerAnalysis
    { powerNormalized :: Maybe Double
    , powerNormalizationSeconds :: Double
    , powerVariabilityIndex :: Maybe Double
    , powerIntensityFactor :: Maybe Double
    , powerStressScore :: Maybe Double
    , powerWattsPerKilogram :: Maybe Double
    , powerWorkJoules :: Maybe Double
    , powerEfficiency :: Maybe Double
    , powerDecouplingPercent :: Maybe Double
    , powerThresholdWatts :: Maybe Double
    , powerAthleteKilograms :: Maybe Double
    }
    deriving (Eq, Show, Generic)

data RunningAnalysis = RunningAnalysis
    { runningSteps :: Maybe Double
    , runningFlightSeconds :: Maybe Double
    , runningVerticalRatioPercent :: Maybe Double
    , runningFlightRatioPercent :: Maybe Double
    , runningEffectiveness :: Maybe Double
    }
    deriving (Eq, Show, Generic)

data SplitSet = SplitSet
    { splitLengthMetres :: Double
    , distanceSplits :: Vector DistanceSplit
    }
    deriving (Eq, Show, Generic)

data DistanceSplit = DistanceSplit
    { splitIndex :: Int
    , splitStartSeconds :: Double
    , splitEndSeconds :: Double
    , splitDistanceMetres :: Double
    , splitAverageSpeed :: Double
    , splitHeartRate :: Maybe Double
    , splitPower :: Maybe Double
    , splitCadence :: Maybe Double
    , splitElevationChange :: Maybe Double
    }
    deriving (Eq, Show, Generic)

data SplitComparison = SplitComparison
    { firstHalfSpeed :: Double
    , secondHalfSpeed :: Double
    , secondHalfChangePercent :: Double
    }
    deriving (Eq, Show, Generic)

data MetricRelationship = MetricRelationship
    { relationshipX :: MetricKind
    , relationshipY :: MetricKind
    , relationshipSampleCount :: Int
    , relationshipCorrelation :: Maybe Double
    , relationshipPoints :: Vector RelationshipPoint
    }
    deriving (Eq, Show, Generic)

data RelationshipPoint = RelationshipPoint
    { relationshipXValue :: Double
    , relationshipYValue :: Double
    }
    deriving (Eq, Show, Generic)
