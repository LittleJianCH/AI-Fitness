{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Api.Codec (ViaJSON (..), ViaEnum (..), jsonOptions) where

import Control.Lens ((&), (?~))
import Data.Aeson
    ( FromJSON (..)
    , GFromJSON
    , GToJSON'
    , Options (..)
    , SumEncoding (..)
    , ToJSON (..)
    , Value (..)
    , Zero
    , defaultOptions
    , genericParseJSON
    , genericToJSON
    )
import Data.Aeson.Types (Parser, parseEither)
import Data.Char (toLower)
import Data.Foldable (traverse_)
import Data.OpenApi
    ( ToParamSchema (..)
    , ToSchema (..)
    , fromAesonOptions
    , genericDeclareNamedSchema
    , name
    , toSchema
    )
import Data.OpenApi.Internal.Schema (GToSchema)
import Data.Proxy (Proxy (..))
import qualified Data.Text as Text
import Data.Typeable (Typeable)
import qualified Data.Typeable as Type
import GHC.Generics (Generic, Rep)
import Web.HttpApiData (FromHttpApiData (..))

-- One encoding policy drives both JSON and schema derivation. DTO fields use a
-- leading underscore to avoid Haskell selector collisions with common functions.
newtype ViaJSON a = ViaJSON a

-- Aeson's default single-constructor encoding is an empty array for a lone
-- nullary constructor. Explicit enum tagging keeps even a one-option enum a string.
newtype ViaEnum a = ViaEnum a

instance (Generic a, GToJSON' Value Zero (Rep a)) => ToJSON (ViaEnum a) where
    toJSON (ViaEnum a) = genericToJSON (jsonOptions {tagSingleConstructors = True}) a

instance (Generic a, GFromJSON Zero (Rep a)) => FromJSON (ViaEnum a) where
    parseJSON value = ViaEnum <$> genericParseJSON (jsonOptions {tagSingleConstructors = True}) value

instance (Typeable a, Generic a, GToSchema (Rep a)) => ToSchema (ViaEnum a) where
    declareNamedSchema _ = declareNamedSchema (Proxy :: Proxy (ViaJSON a))

jsonOptions :: Options
jsonOptions =
    defaultOptions
        { fieldLabelModifier = dropWhile (== '_')
        , constructorTagModifier = lowerInitial
        , sumEncoding = TaggedObject "type" "data"
        , omitNothingFields = True
        }
  where
    lowerInitial [] = []
    lowerInitial (x : xs) = toLower x : xs

instance (Generic a, GToJSON' Value Zero (Rep a)) => ToJSON (ViaJSON a) where
    toJSON (ViaJSON a) = genericToJSON jsonOptions a

instance (Generic a, GFromJSON Zero (Rep a)) => FromJSON (ViaJSON a) where
    parseJSON value = rejectNull value *> (ViaJSON <$> genericParseJSON jsonOptions value)

-- V1 uses absent optional fields, never JSON null. PUT replaces an editable
-- document: omitting an optional field clears it. Unknown fields are tolerated
-- for additive evolution, but never used for authorization or persistence.
rejectNull :: Value -> Parser ()
rejectNull Null = fail "JSON null is not supported; omit optional fields"
rejectNull (Object fields) = traverse_ rejectNull fields
rejectNull (Array values) = traverse_ rejectNull values
rejectNull _ = pure ()

instance (Typeable a, Generic a, GToSchema (Rep a)) => ToSchema (ViaJSON a) where
    declareNamedSchema _ =
        (\schema -> schema & name ?~ Text.pack (schemaName (Type.typeRep (Proxy :: Proxy a))))
            <$> genericDeclareNamedSchema (fromAesonOptions jsonOptions) (Proxy :: Proxy a)

-- Include parameters: Page Workout and Page Session must never share a schema.
schemaName :: Type.TypeRep -> String
schemaName representation =
    Type.tyConName constructor <> concatMap (("_" <>) . schemaName) arguments
  where
    (constructor, arguments) = Type.splitTyConApp representation

instance (Generic a, GFromJSON Zero (Rep a)) => FromHttpApiData (ViaJSON a) where
    parseUrlPiece = either (Left . Text.pack) Right . parseEither parseJSON . String

instance (Typeable a, Generic a, GToSchema (Rep a)) => ToParamSchema (ViaJSON a) where
    toParamSchema = toSchema
