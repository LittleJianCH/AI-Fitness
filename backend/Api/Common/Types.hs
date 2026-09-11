{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE KindSignatures #-}

module Api.Common.Types
    ( Id (..)
    , Revision (..)
    , Timestamp (..)
    , Page (..)
    , Problem (..)
    , FieldError (..)
    , RevisionRequest (..)
    ) where

import Api.Codec (ViaJSON (..))
import Api.Scalar (Decimal (..), UTC (..))
import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToParamSchema, ToSchema)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import Data.Vector (Vector)
import GHC.Generics (Generic)
import GHC.TypeLits (Symbol)
import Numeric.Natural (Natural)
import Web.HttpApiData (FromHttpApiData, ToHttpApiData)

newtype Id (resource :: Symbol) = Id UUID
    deriving stock (Eq, Ord, Show)
    deriving (FromJSON, ToJSON, ToSchema, ToParamSchema, FromHttpApiData, ToHttpApiData) via UUID
newtype Revision = Revision Natural
    deriving stock (Eq, Ord, Show)
    deriving (FromJSON, ToJSON, ToSchema, ToParamSchema, FromHttpApiData, ToHttpApiData) via Decimal
newtype Timestamp = Timestamp UTCTime
    deriving stock (Eq, Ord, Show)
    deriving (FromJSON, ToJSON, ToSchema, ToParamSchema, FromHttpApiData, ToHttpApiData) via UTC

data Page a = Page {_items :: Vector a, _nextCursor :: Maybe Text}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON (Page a))

data Problem = Problem
    { _code :: Text
    , _message :: Text
    , _requestId :: Text
    , _fields :: [FieldError]
    }
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON Problem)

data FieldError = FieldError {_path :: Text, _code :: Text, _message :: Text}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON FieldError)

newtype RevisionRequest = RevisionRequest {_expectedRevision :: Revision}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON RevisionRequest)
