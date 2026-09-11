{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.Workout.Cycling.Codec () where

import Api.Codec (ViaJSON (..))
import Api.Workout.Common.Codec ()
import Api.Workout.Measurement.Codec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Workout.Cycling.Types

deriving via (ViaJSON CyclingData) instance ToJSON CyclingData
deriving via (ViaJSON CyclingData) instance FromJSON CyclingData
deriving via (ViaJSON CyclingData) instance ToSchema CyclingData

deriving via (ViaJSON PedalingData) instance ToJSON PedalingData
deriving via (ViaJSON PedalingData) instance FromJSON PedalingData
deriving via (ViaJSON PedalingData) instance ToSchema PedalingData

deriving via (ViaJSON GearChange) instance ToJSON GearChange
deriving via (ViaJSON GearChange) instance FromJSON GearChange
deriving via (ViaJSON GearChange) instance ToSchema GearChange

deriving via (ViaJSON Gear) instance ToJSON Gear
deriving via (ViaJSON Gear) instance FromJSON Gear
deriving via (ViaJSON Gear) instance ToSchema Gear

deriving via (ViaJSON CyclingSummary) instance ToJSON CyclingSummary
deriving via (ViaJSON CyclingSummary) instance FromJSON CyclingSummary
deriving via (ViaJSON CyclingSummary) instance ToSchema CyclingSummary

deriving via (ViaJSON CyclingContext) instance ToJSON CyclingContext
deriving via (ViaJSON CyclingContext) instance FromJSON CyclingContext
deriving via (ViaJSON CyclingContext) instance ToSchema CyclingContext
