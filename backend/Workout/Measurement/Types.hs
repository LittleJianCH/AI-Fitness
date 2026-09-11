-- Unit-bearing measurements. Constructors describe data; validation is separate.
module Workout.Measurement.Types
    ( HeartRate (..)
    , Power (..)
    , CyclingCadence (..)
    , RunningCadence (..)
    , Speed (..)
    , Distance (..)
    , Altitude (..)
    , Duration (..)
    , Energy (..)
    , Temperature (..)
    , Percentage (..)
    , Grade (..)
    , Bearing (..)
    , Mass (..)
    , IntensityFactor (..)
    , TrainingStress (..)
    , Position (..)
    , Timed (..)
    , TimeSeries
    , TimeRange (..)
    , Statistics (..)
    , Summaries (..)
    , Calculated (..)
    , ExtensionField (..)
    , ExtensionData (..)
    , Lap (..)
    ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Vector (Vector)
import Workout.Identity.Types (WorkoutRevision)

newtype HeartRate = HeartRate Double deriving (Eq, Ord, Show) -- bpm
newtype Power = Power Double deriving (Eq, Ord, Show) -- W
newtype CyclingCadence = CyclingCadence Double deriving (Eq, Ord, Show) -- rpm
newtype RunningCadence = RunningCadence Double deriving (Eq, Ord, Show) -- steps/min, both feet
newtype Speed = Speed Double deriving (Eq, Ord, Show) -- m/s
newtype Distance = Distance Double deriving (Eq, Ord, Show) -- m
newtype Altitude = Altitude Double deriving (Eq, Ord, Show) -- m, may be negative
newtype Duration = Duration Double deriving (Eq, Ord, Show) -- seconds
newtype Energy = Energy Double deriving (Eq, Ord, Show) -- joules
newtype Temperature = Temperature Double deriving (Eq, Ord, Show) -- Celsius
newtype Percentage = Percentage Double deriving (Eq, Ord, Show) -- 0..100
newtype Grade = Grade Double deriving (Eq, Ord, Show) -- percent, signed
newtype Bearing = Bearing Double deriving (Eq, Ord, Show) -- degrees clockwise from north, [0,360)
newtype Mass = Mass Double deriving (Eq, Ord, Show) -- kg
newtype IntensityFactor = IntensityFactor Double deriving (Eq, Ord, Show) -- ratio, may exceed 1
newtype TrainingStress = TrainingStress Double deriving (Eq, Ord, Show) -- score, not a percentage

-- Latitude and longitude are degrees in WGS84.
data Position = Position
    { latitude :: Double
    , longitude :: Double
    }
    deriving (Eq, Show)

data Timed a = Timed
    { timestamp :: UTCTime
    , value :: a
    }
    deriving (Eq, Show)

-- Canonical measurements have strictly increasing timestamps; events may tie.
-- Empty means no samples. Gaps are not filled or interpreted as zeroes.
type TimeSeries a = Vector (Timed a)

data TimeRange = TimeRange
    { rangeStart :: UTCTime
    , rangeEnd :: UTCTime
    }
    deriving (Eq, Show)

data Statistics a = Statistics
    { minimumValue :: Maybe a
    , averageValue :: Maybe a
    , maximumValue :: Maybe a
    }
    deriving (Eq, Show)

-- Recorded values may be the only available facts (e.g. manual input).
-- Recalculation must not silently overwrite them.
data Summaries a = Summaries
    { recordedSummary :: a
    , calculatedSummary :: Maybe (Calculated a)
    }
    deriving (Eq, Show)

data Calculated a = Calculated
    { calculationInputRevision :: WorkoutRevision
    , calculationConfig :: Text -- relevant configuration identifier
    , calculationMethod :: Text -- algorithm name/version
    , calculatedAt :: UTCTime
    , calculationValue :: a
    }
    deriving (Eq, Show)

-- A namespaced canonical key, not a FIT field number or binary encoding.
-- An empty stream can retain a definition without inventing observations.
data ExtensionField = ExtensionField
    { extensionKey :: Text
    , extensionLabel :: Text
    , extensionData :: ExtensionData
    }
    deriving (Eq, Show)

data ExtensionData
    = NumericExtension (Maybe Text) (TimeSeries Double) (Statistics Double)
    | TextExtension (TimeSeries Text) (Maybe Text)
    | BooleanExtension (TimeSeries Bool) (Maybe Bool)
    deriving (Eq, Show)

data Lap summary = Lap
    { lapRange :: TimeRange
    , lapLabel :: Maybe Text
    , lapSummary :: Summaries summary
    , lapExtensions :: Vector ExtensionField
    }
    deriving (Eq, Show)
