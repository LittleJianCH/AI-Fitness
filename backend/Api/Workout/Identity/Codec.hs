{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.Workout.Identity.Codec () where

import Api.Scalar (Decimal (..))
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.OpenApi (ToParamSchema (..), ToSchema (..))
import Data.Proxy (Proxy (..))
import qualified Data.Text as Text
import Data.UUID.Types (UUID)
import Web.HttpApiData (FromHttpApiData (..), ToHttpApiData (..))
import Workout.Identity.Types

deriving via UUID instance ToJSON WorkoutId
deriving via UUID instance FromJSON WorkoutId
deriving via UUID instance ToSchema WorkoutId
deriving via UUID instance ToParamSchema WorkoutId
deriving via UUID instance FromHttpApiData WorkoutId
deriving via UUID instance ToHttpApiData WorkoutId

deriving via UUID instance ToJSON WorkoutGroupId
deriving via UUID instance FromJSON WorkoutGroupId
deriving via UUID instance ToSchema WorkoutGroupId
deriving via UUID instance ToParamSchema WorkoutGroupId
deriving via UUID instance FromHttpApiData WorkoutGroupId
deriving via UUID instance ToHttpApiData WorkoutGroupId

instance ToJSON WorkoutRevision where
    toJSON (WorkoutRevision revision) = toJSON (Text.pack (show revision))

instance FromJSON WorkoutRevision where
    parseJSON input = (\(Decimal revision) -> WorkoutRevision (toInteger revision)) <$> parseJSON input

instance FromHttpApiData WorkoutRevision where
    parseUrlPiece input = (\(Decimal revision) -> WorkoutRevision (toInteger revision)) <$> parseUrlPiece input

instance ToHttpApiData WorkoutRevision where
    toUrlPiece (WorkoutRevision revision) = Text.pack (show revision)

instance ToParamSchema WorkoutRevision where
    toParamSchema _ = toParamSchema (Proxy :: Proxy Decimal)

instance ToSchema WorkoutRevision where
    declareNamedSchema _ = declareNamedSchema (Proxy :: Proxy Decimal)
