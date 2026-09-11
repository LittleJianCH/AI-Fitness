{-# LANGUAGE DeriveGeneric #-}

module Workout.Cycling.Types
    ( CyclingData (..)
    , PedalingData (..)
    , GearChange (..)
    , Gear (..)
    , CyclingSummary (..)
    , CyclingContext (..)
    ) where

import Data.Text (Text)
import Data.Vector (Vector)
import GHC.Generics (Generic)
import Workout.Common.Types
import Workout.Measurement.Types

-- The initial cycling baseline is heart rate, power, speed, altitude and GPS
-- in cyclingMotion, plus cyclingCadence (rpm). Every stream is independently
-- sampled; an unavailable sensor leaves an empty stream.
data CyclingData = CyclingData
    { cyclingMotion :: MotionData
    , cyclingCadence :: TimeSeries CyclingCadence
    , cyclingPedaling :: PedalingData
    , cyclingGearChanges :: Vector (Timed GearChange)
    , cyclingSummary :: Summaries CyclingSummary
    , cyclingLaps :: Vector (Lap CyclingSummary)
    , cyclingContext :: CyclingContext
    }
    deriving (Eq, Show, Generic)

data PedalingData = PedalingData
    { leftPowerShare :: TimeSeries Percentage -- right share = 100 - left
    , leftSmoothness :: TimeSeries Percentage
    , rightSmoothness :: TimeSeries Percentage
    , leftTorqueEffectiveness :: TimeSeries Percentage
    , rightTorqueEffectiveness :: TimeSeries Percentage
    }
    deriving (Eq, Show, Generic)

-- Each event records the known gearing after the change. Either side can be absent.
data GearChange = GearChange
    { frontGear :: Maybe Gear
    , rearGear :: Maybe Gear
    }
    deriving (Eq, Show, Generic)

data Gear = Gear
    { gearIndex :: Maybe Int -- 1-based, innermost first
    , gearTeeth :: Maybe Int
    }
    deriving (Eq, Show, Generic)

data CyclingSummary = CyclingSummary
    { cyclingCommonSummary :: CommonSummary
    , summaryCyclingCadence :: Statistics CyclingCadence
    , summaryLeftPowerShare :: Maybe Percentage
    , summaryLeftSmoothness :: Maybe Percentage
    , summaryRightSmoothness :: Maybe Percentage
    , summaryLeftTorqueEffectiveness :: Maybe Percentage
    , summaryRightTorqueEffectiveness :: Maybe Percentage
    }
    deriving (Eq, Show, Generic)

-- Values captured for this workout, not references to a mutable current profile.
data CyclingContext = CyclingContext
    { cyclingDiscipline :: Maybe Text -- e.g. road, gravel, indoor
    , bicycleName :: Maybe Text
    , bicycleMass :: Maybe Mass
    , wheelCircumference :: Maybe Distance
    }
    deriving (Eq, Show, Generic)
