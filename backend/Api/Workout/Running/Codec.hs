{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.Workout.Running.Codec () where

import Api.Codec (ViaJSON (..))
import Api.Workout.Common.Codec ()
import Api.Workout.Measurement.Codec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Workout.Running.Types

deriving via (ViaJSON RunningData) instance ToJSON RunningData
deriving via (ViaJSON RunningData) instance FromJSON RunningData
deriving via (ViaJSON RunningData) instance ToSchema RunningData

deriving via (ViaJSON RunningDynamics) instance ToJSON RunningDynamics
deriving via (ViaJSON RunningDynamics) instance FromJSON RunningDynamics
deriving via (ViaJSON RunningDynamics) instance ToSchema RunningDynamics

deriving via (ViaJSON RunningSummary) instance ToJSON RunningSummary
deriving via (ViaJSON RunningSummary) instance FromJSON RunningSummary
deriving via (ViaJSON RunningSummary) instance ToSchema RunningSummary
