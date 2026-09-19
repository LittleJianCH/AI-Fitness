{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.Settings.Codec () where

import Api.Codec (ViaJSON (..))
import Api.Scalar (Decimal (..))
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Profile.Types

deriving via Decimal instance ToJSON SettingsRevision
deriving via Decimal instance FromJSON SettingsRevision
deriving via Decimal instance ToSchema SettingsRevision
deriving via ViaJSON Appearance instance ToJSON Appearance
deriving via ViaJSON Appearance instance FromJSON Appearance
deriving via ViaJSON Appearance instance ToSchema Appearance
deriving via ViaJSON EquipmentKind instance ToJSON EquipmentKind
deriving via ViaJSON EquipmentKind instance FromJSON EquipmentKind
deriving via ViaJSON EquipmentKind instance ToSchema EquipmentKind
deriving via ViaJSON LoadWeighting instance ToJSON LoadWeighting
deriving via ViaJSON LoadWeighting instance FromJSON LoadWeighting
deriving via ViaJSON LoadWeighting instance ToSchema LoadWeighting
deriving via ViaJSON SoftwareSettings instance ToJSON SoftwareSettings
deriving via ViaJSON SoftwareSettings instance FromJSON SoftwareSettings
deriving via ViaJSON SoftwareSettings instance ToSchema SoftwareSettings
deriving via ViaJSON BodyProfile instance ToJSON BodyProfile
deriving via ViaJSON BodyProfile instance FromJSON BodyProfile
deriving via ViaJSON BodyProfile instance ToSchema BodyProfile
deriving via ViaJSON SportProfile instance ToJSON SportProfile
deriving via ViaJSON SportProfile instance FromJSON SportProfile
deriving via ViaJSON SportProfile instance ToSchema SportProfile
deriving via ViaJSON HeartRateProfile instance ToJSON HeartRateProfile
deriving via ViaJSON HeartRateProfile instance FromJSON HeartRateProfile
deriving via ViaJSON HeartRateProfile instance ToSchema HeartRateProfile
deriving via ViaJSON Equipment instance ToJSON Equipment
deriving via ViaJSON Equipment instance FromJSON Equipment
deriving via ViaJSON Equipment instance ToSchema Equipment
deriving via ViaJSON UserSettings instance ToJSON UserSettings
deriving via ViaJSON UserSettings instance FromJSON UserSettings
deriving via ViaJSON UserSettings instance ToSchema UserSettings
