{-# LANGUAGE OverloadedStrings #-}

module Storage.Codec (param, column, userIdValue, userIdColumn, validText, jsonErrors) where

import Data.Aeson (Value (..))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import Data.Functor.Contravariant (contramap)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Vector as V
import qualified Hasql.Decoders as D
import qualified Hasql.Encoders as E
import Storage.User.Types (UserId (..))
import Workout.Validation.Types (ValidationError (..))

-- PostgreSQL text and JSONB cannot represent U+0000. Reject it explicitly;
-- never silently strip characters from canonical user content.
validText :: Text -> Bool
validText = not . Text.any (== '\0')

jsonErrors :: Text -> Value -> [ValidationError]
jsonErrors path value = case value of
    String text -> [ValidationError path "Text cannot contain U+0000" | not (validText text)]
    Object fields -> concat [jsonErrors (path <> "." <> Key.toText key) item | (key, item) <- KM.toList fields]
    Array items -> concat (V.toList (V.imap (\index -> jsonErrors (path <> "." <> Text.pack (show index))) items))
    _ -> []

param :: E.Value a -> E.Params a
param = E.param . E.nonNullable

column :: D.Value a -> D.Row a
column = D.column . D.nonNullable

userIdValue :: E.Value UserId
userIdValue = contramap (\(UserId value) -> value) E.uuid

userIdColumn :: D.Row UserId
userIdColumn = UserId <$> column D.uuid
