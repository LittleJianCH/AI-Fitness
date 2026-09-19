{-# LANGUAGE DeriveGeneric #-}

module Profile.Types where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import Data.Vector (Vector)
import GHC.Generics (Generic)
import Numeric.Natural (Natural)

newtype SettingsRevision = SettingsRevision Natural deriving (Eq, Ord, Show)
data Appearance = SystemAppearance | LightAppearance | DarkAppearance deriving (Eq, Show, Generic)
data EquipmentKind = Bicycle | RunningShoes deriving (Eq, Show, Generic)
data LoadWeighting = Exponent192 | Exponent167 deriving (Eq, Show, Generic)

newtype SoftwareSettings = SoftwareSettings
    { softwareAppearance :: Appearance
    }
    deriving (Eq, Show, Generic)

-- A new entry replaces the complete parameter snapshot from its effective time.
-- Historical entries are immutable; corrections are explicit subsequent entries.
data BodyProfile = BodyProfile
    { bodyProfileId :: UUID
    , bodyEffectiveFrom :: UTCTime
    , bodyMassKilograms :: Maybe Double
    , bodyHeightMetres :: Maybe Double
    , bodyCycling :: SportProfile
    , bodyRunning :: SportProfile
    }
    deriving (Eq, Show, Generic)

data SportProfile = SportProfile
    { sportThresholdWatts :: Maybe Double
    , sportHeartRate :: Maybe HeartRateProfile
    }
    deriving (Eq, Show, Generic)

data HeartRateProfile = HeartRateProfile
    { heartRateResting :: Double
    , heartRateMaximum :: Double
    , heartRateThreshold :: Double
    , heartRateWeighting :: LoadWeighting
    }
    deriving (Eq, Show, Generic)

data Equipment = Equipment
    { equipmentId :: UUID
    , equipmentKind :: EquipmentKind
    , equipmentName :: Text
    , equipmentMassKilograms :: Maybe Double
    , equipmentRetired :: Bool
    }
    deriving (Eq, Show, Generic)

data UserSettings = UserSettings
    { settingsRevision :: SettingsRevision
    , settingsSoftware :: SoftwareSettings
    , settingsBodyProfiles :: Vector BodyProfile
    , settingsEquipment :: Vector Equipment
    }
    deriving (Eq, Show, Generic)
