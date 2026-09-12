{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module Api.Boundary (withRequest) where

import Api.Common.Types (Problem (..))
import App.Types
import Control.Exception (SomeAsyncException, SomeException, fromException, throwIO, try)
import Data.Aeson (encode)
import qualified Data.ByteString as BS
import Data.IORef (atomicModifyIORef', newIORef)
import qualified Data.Text.Encoding as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import Import.Fit.Decode (maxFitBytes)
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Internal (ResponseReceived (..))

-- Request IDs and generic errors never echo credentials or health payloads.
withRequest :: Environment -> (RequestContext -> Application) -> Application
withRequest environment route original respond = do
    rid <- UUID.toText <$> UUID.nextRandom
    let context = RequestContext original rid
        limit =
            if take 3 (pathInfo original) == ["api", "v1", "auth"]
                then 16384
                else
                    if pathInfo original == ["api", "v1", "imports", "fit"]
                        then maxFitBytes
                        else maxJsonBytes (settings environment)
        failure status code message =
            responseLBS
                status
                [(hContentType, "application/json")]
                (encode (Problem code message rid []))
        finish response =
            respond $
                mapResponseHeaders
                    ( \hs ->
                        ("X-Request-Id", Text.encodeUtf8 rid)
                            : (hCacheControl, "no-store")
                            : filter ((/= hCacheControl) . fst) hs
                    )
                    ( if statusCode (responseStatus response) >= 400
                        && lookup hContentType (responseHeaders response) /= Just "application/json"
                        then failure (responseStatus response) "invalid_request" "The request could not be processed"
                        else response
                    )
    -- Catch before sending to WAI; never send a second response after a socket
    -- failure in the responder. These handlers produce finite JSON responses.
    outcome <- try $ do
        body <- readLimited limit original
        case body of
            Nothing -> pure (failure status413 "payload_too_large" "Request body is too large")
            Just bytes -> do
                ref <- newIORef bytes
                let next = atomicModifyIORef' ref (BS.empty,)
                    req = setRequestBodyChunks next original
                result <- newIORef Nothing
                _ <-
                    route
                        (context {request = req})
                        req
                        (\response -> atomicModifyIORef' result (const (Just response, ResponseReceived)))
                value <- atomicModifyIORef' result (Nothing,)
                maybe (fail "Application returned no response") pure value
    case outcome of
        Right response -> finish response
        Left err -> case fromException err :: Maybe SomeAsyncException of
            Just _ -> throwIO (err :: SomeException)
            Nothing -> finish (failure status500 "internal_error" "Request failed")

readLimited :: Int -> Request -> IO (Maybe BS.ByteString)
readLimited limit req = case requestBodyLength req of
    KnownLength lengthBytes | lengthBytes > fromIntegral limit -> pure Nothing
    _ -> go 0 []
  where
    go size chunks = do
        chunk <- getRequestBodyChunk req
        let nextSize = size + BS.length chunk
        if nextSize > limit
            then pure Nothing
            else
                if BS.null chunk
                    then pure (Just (BS.concat (reverse chunks)))
                    else go nextSize (chunk : chunks)
