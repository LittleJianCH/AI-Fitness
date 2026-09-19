{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.Analysis.Codec () where

import Analysis.Fatigue.Request
import Api.Codec (ViaJSON (..))
import Api.Settings.Codec ()
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)

deriving via ViaJSON CalendarDay instance ToJSON CalendarDay
deriving via ViaJSON CalendarDay instance FromJSON CalendarDay
deriving via ViaJSON CalendarDay instance ToSchema CalendarDay
deriving via ViaJSON TrainingHistoryRequest instance ToJSON TrainingHistoryRequest
deriving via ViaJSON TrainingHistoryRequest instance FromJSON TrainingHistoryRequest
deriving via ViaJSON TrainingHistoryRequest instance ToSchema TrainingHistoryRequest
deriving via ViaJSON TrainingHistory instance ToJSON TrainingHistory
deriving via ViaJSON TrainingHistory instance FromJSON TrainingHistory
deriving via ViaJSON TrainingHistory instance ToSchema TrainingHistory
deriving via ViaJSON TrainingDay instance ToJSON TrainingDay
deriving via ViaJSON TrainingDay instance FromJSON TrainingDay
deriving via ViaJSON TrainingDay instance ToSchema TrainingDay
