{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.Workout.Common.Codec () where

import Api.Codec (ViaJSON (..))
import Api.Workout.Measurement.Codec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Workout.Common.Types

deriving via (ViaJSON MotionData) instance ToJSON MotionData
deriving via (ViaJSON MotionData) instance FromJSON MotionData
deriving via (ViaJSON MotionData) instance ToSchema MotionData

deriving via (ViaJSON EnvironmentData) instance ToJSON EnvironmentData
deriving via (ViaJSON EnvironmentData) instance FromJSON EnvironmentData
deriving via (ViaJSON EnvironmentData) instance ToSchema EnvironmentData

deriving via (ViaJSON CommonSummary) instance ToJSON CommonSummary
deriving via (ViaJSON CommonSummary) instance FromJSON CommonSummary
deriving via (ViaJSON CommonSummary) instance ToSchema CommonSummary
