{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.Workout.PowerCurveCodec () where

import Api.Codec (ViaJSON (..))
import Api.Workout.Identity.Codec ()
import Api.Workout.Measurement.Codec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Workout.PowerCurve.Types

deriving via (ViaJSON PowerCurve) instance ToJSON PowerCurve
deriving via (ViaJSON PowerCurve) instance FromJSON PowerCurve
deriving via (ViaJSON PowerCurve) instance ToSchema PowerCurve
deriving via (ViaJSON PowerCurvePoint) instance ToJSON PowerCurvePoint
deriving via (ViaJSON PowerCurvePoint) instance FromJSON PowerCurvePoint
deriving via (ViaJSON PowerCurvePoint) instance ToSchema PowerCurvePoint
deriving via (ViaJSON PowerEffort) instance ToJSON PowerEffort
deriving via (ViaJSON PowerEffort) instance FromJSON PowerEffort
deriving via (ViaJSON PowerEffort) instance ToSchema PowerEffort
