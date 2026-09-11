{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Api.Scalar (Decimal (..), UTC (..), Unit (..)) where

import Control.Lens ((&), (?~))
import Data.Aeson (FromJSON (..), ToJSON (..), withText)
import Data.Char (isDigit)
import Data.OpenApi
    ( NamedSchema (..)
    , OpenApiType (OpenApiString)
    , ToParamSchema (..)
    , ToSchema (..)
    , description
    , format
    , toSchema
    , type_
    )
import qualified Data.OpenApi as OpenApi
import Data.Proxy (Proxy (..))
import qualified Data.Text as Text
import Data.Time (UTCTime)
import GHC.TypeLits (KnownSymbol, Symbol, symbolVal)
import Numeric.Natural (Natural)
import Text.Read (readMaybe)
import Web.HttpApiData (FromHttpApiData (..), ToHttpApiData (..))

newtype Decimal = Decimal Natural
newtype UTC = UTC UTCTime
newtype Unit (name :: Symbol) (unit :: Symbol) = Unit Double

instance (KnownSymbol name, KnownSymbol unit) => ToSchema (Unit name unit) where
    declareNamedSchema _ =
        pure
            ( NamedSchema
                (Just (Text.pack (symbolVal (Proxy :: Proxy name))))
                (toSchema (Proxy :: Proxy Double) & description ?~ Text.pack (symbolVal (Proxy :: Proxy unit)))
            )

instance ToJSON Decimal where
    toJSON (Decimal value) = toJSON (Text.pack (show value))

instance FromJSON Decimal where
    parseJSON = withText "decimal revision" $ either (fail . Text.unpack) pure . parseUrlPiece

instance FromHttpApiData Decimal where
    parseUrlPiece text
        | text == "0" || (Text.take 1 text /= "0" && not (Text.null text) && Text.all isDigit text) =
            maybe (Left "Invalid revision") (Right . Decimal) (readMaybe (Text.unpack text))
        | otherwise = Left "Expected an unsigned decimal string without leading zeroes"

instance ToHttpApiData Decimal where
    toUrlPiece (Decimal value) = Text.pack (show value)

instance ToParamSchema Decimal where
    toParamSchema _ = mempty & type_ ?~ OpenApiString & OpenApi.pattern ?~ "^(0|[1-9][0-9]*)$"

instance ToSchema Decimal where
    declareNamedSchema proxy = pure (NamedSchema (Just "Revision") (toParamSchema proxy))

instance ToJSON UTC where
    toJSON (UTC time) = toJSON time

instance FromJSON UTC where
    parseJSON value = UTC <$> parseJSON value

instance ToHttpApiData UTC where
    toUrlPiece (UTC time) = toUrlPiece time

instance FromHttpApiData UTC where
    parseUrlPiece text = UTC <$> parseUrlPiece text

instance ToParamSchema UTC where
    toParamSchema _ = mempty & type_ ?~ OpenApiString & format ?~ "date-time"

instance ToSchema UTC where
    declareNamedSchema proxy = pure (NamedSchema (Just "Timestamp") (toParamSchema proxy))
