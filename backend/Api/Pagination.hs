{-# LANGUAGE OverloadedStrings #-}

module Api.Pagination (pageLimit, readCursor, writeCursor, page) where

import Api.Common.Types (Page (..))
import Api.Error (problem)
import App.Types
import qualified Auth.Token as Token
import Data.Aeson (FromJSON, Result (..), ToJSON, Value, decodeStrict, encode, fromJSON)
import Data.ByteArray (constEq)
import qualified Data.ByteString.Lazy as LBS
import Data.Int (Int32)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Vector as V
import Servant (Handler)

pageLimit :: RequestContext -> Maybe Int32 -> Handler Int
pageLimit context value = case maybe 50 fromIntegral value of
    n | n >= 1 && n <= 100 -> pure n
    _ -> problem context 400 "invalid_query" "Limit must be between 1 and 100"

readCursor
    :: (FromJSON a) => Environment -> RequestContext -> Value -> Maybe Text -> Handler (Maybe a)
readCursor _ _ _ Nothing = pure Nothing
readCursor environment context scope (Just token) = maybe invalid (pure . Just) $ do
    if Text.length token <= 8192 then Just () else Nothing
    (payloadText, signatureText) <- case Text.splitOn "." token of
        [p, s] -> Just (p, s)
        _ -> Nothing
    payload <- Token.decodeHex payloadText
    signature <- Token.decodeHex signatureText
    if Token.sign (cursorKey environment) payload `constEq` signature then Just () else Nothing
    (actualScope, position) <- decodeStrict payload
    if actualScope == scope
        then case fromJSON position of
            Success value -> Just value
            Error _ -> Nothing
        else Nothing
  where
    invalid = problem context 400 "invalid_cursor" "Cursor is invalid for this collection"

writeCursor :: (ToJSON a) => Environment -> Value -> a -> Text
writeCursor environment scope position = Token.encodeHex payload <> "." <> Token.encodeHex (Token.sign (cursorKey environment) payload)
  where
    payload = LBS.toStrict (encode (scope, position))

page :: Int -> (a -> Text) -> V.Vector a -> Page a
page limit cursor rows = Page visible next
  where
    visible = V.take limit rows
    next = if V.length rows > limit then cursor <$> (visible V.!? (limit - 1)) else Nothing
