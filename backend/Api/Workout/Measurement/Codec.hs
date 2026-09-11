{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.Workout.Measurement.Codec () where

import Api.Codec (ViaJSON (..))
import Api.Scalar (Unit (..))
import Api.Workout.Identity.Codec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Data.OpenApi.Internal.Schema (GToSchema)
import Data.Typeable (Typeable)
import GHC.Generics (Rep)
import Workout.Measurement.Types

deriving via Double instance ToJSON HeartRate
deriving via Double instance FromJSON HeartRate
deriving via (Unit "HeartRate" "beats/minute") instance ToSchema HeartRate

deriving via Double instance ToJSON Power
deriving via Double instance FromJSON Power
deriving via (Unit "Power" "watts") instance ToSchema Power

deriving via Double instance ToJSON CyclingCadence
deriving via Double instance FromJSON CyclingCadence
deriving via (Unit "CyclingCadence" "revolutions/minute") instance ToSchema CyclingCadence

deriving via Double instance ToJSON RunningCadence
deriving via Double instance FromJSON RunningCadence
deriving via (Unit "RunningCadence" "steps/minute, both feet") instance ToSchema RunningCadence

deriving via Double instance ToJSON Speed
deriving via Double instance FromJSON Speed
deriving via (Unit "Speed" "metres/second") instance ToSchema Speed

deriving via Double instance ToJSON Distance
deriving via Double instance FromJSON Distance
deriving via (Unit "Distance" "metres") instance ToSchema Distance

deriving via Double instance ToJSON Altitude
deriving via Double instance FromJSON Altitude
deriving via (Unit "Altitude" "metres") instance ToSchema Altitude

deriving via Double instance ToJSON Duration
deriving via Double instance FromJSON Duration
deriving via (Unit "Duration" "seconds") instance ToSchema Duration

deriving via Double instance ToJSON Energy
deriving via Double instance FromJSON Energy
deriving via (Unit "Energy" "joules") instance ToSchema Energy

deriving via Double instance ToJSON Temperature
deriving via Double instance FromJSON Temperature
deriving via (Unit "Temperature" "degrees Celsius") instance ToSchema Temperature

deriving via Double instance ToJSON Percentage
deriving via Double instance FromJSON Percentage
deriving via (Unit "Percentage" "percent, 0..100") instance ToSchema Percentage

deriving via Double instance ToJSON Grade
deriving via Double instance FromJSON Grade
deriving via (Unit "Grade" "percent, signed") instance ToSchema Grade

deriving via Double instance ToJSON Bearing
deriving via Double instance FromJSON Bearing
deriving via (Unit "Bearing" "degrees clockwise from north, [0,360)") instance ToSchema Bearing

deriving via Double instance ToJSON Mass
deriving via Double instance FromJSON Mass
deriving via (Unit "Mass" "kilograms") instance ToSchema Mass

deriving via Double instance ToJSON IntensityFactor
deriving via Double instance FromJSON IntensityFactor
deriving via (Unit "IntensityFactor" "dimensionless ratio") instance ToSchema IntensityFactor

deriving via Double instance ToJSON TrainingStress
deriving via Double instance FromJSON TrainingStress
deriving via (Unit "TrainingStress" "training stress score") instance ToSchema TrainingStress

deriving via (ViaJSON ExtensionData) instance ToJSON ExtensionData
deriving via (ViaJSON ExtensionData) instance FromJSON ExtensionData
deriving via (ViaJSON ExtensionData) instance ToSchema ExtensionData

deriving via (ViaJSON Position) instance ToJSON Position
deriving via (ViaJSON Position) instance FromJSON Position
deriving via (ViaJSON Position) instance ToSchema Position

deriving via (ViaJSON TimeRange) instance ToJSON TimeRange
deriving via (ViaJSON TimeRange) instance FromJSON TimeRange
deriving via (ViaJSON TimeRange) instance ToSchema TimeRange

deriving via (ViaJSON ExtensionField) instance ToJSON ExtensionField
deriving via (ViaJSON ExtensionField) instance FromJSON ExtensionField
deriving via (ViaJSON ExtensionField) instance ToSchema ExtensionField

deriving via (ViaJSON (Timed a)) instance (ToJSON a) => ToJSON (Timed a)
deriving via (ViaJSON (Timed a)) instance (FromJSON a) => FromJSON (Timed a)
deriving via
    (ViaJSON (Timed a))
    instance
        (Typeable a, GToSchema (Rep (Timed a))) => ToSchema (Timed a)

deriving via (ViaJSON (Statistics a)) instance (ToJSON a) => ToJSON (Statistics a)
deriving via (ViaJSON (Statistics a)) instance (FromJSON a) => FromJSON (Statistics a)
deriving via
    (ViaJSON (Statistics a))
    instance
        (Typeable a, GToSchema (Rep (Statistics a))) => ToSchema (Statistics a)

deriving via (ViaJSON (Summaries a)) instance (ToJSON a) => ToJSON (Summaries a)
deriving via (ViaJSON (Summaries a)) instance (FromJSON a) => FromJSON (Summaries a)
deriving via
    (ViaJSON (Summaries a))
    instance
        (Typeable a, GToSchema (Rep (Summaries a))) => ToSchema (Summaries a)

deriving via (ViaJSON (Calculated a)) instance (ToJSON a) => ToJSON (Calculated a)
deriving via (ViaJSON (Calculated a)) instance (FromJSON a) => FromJSON (Calculated a)
deriving via
    (ViaJSON (Calculated a))
    instance
        (Typeable a, GToSchema (Rep (Calculated a))) => ToSchema (Calculated a)

deriving via (ViaJSON (Lap a)) instance (ToJSON a) => ToJSON (Lap a)
deriving via (ViaJSON (Lap a)) instance (FromJSON a) => FromJSON (Lap a)
deriving via (ViaJSON (Lap a)) instance (Typeable a, GToSchema (Rep (Lap a))) => ToSchema (Lap a)
