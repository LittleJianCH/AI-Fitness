{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module Api.Boundary (withRequest) where

import Api.Common.Types (Problem (..))
import App.Admission (withAdmission)
import qualified App.Diagnostics as Diagnostics
import App.Types
import Control.Exception
    ( IOException
    , SomeAsyncException
    , SomeException
    , fromException
    , throwIO
    , try
    )
import Data.Aeson (encode)
import qualified Data.ByteString as BS
import Data.IORef (atomicModifyIORef', newIORef, readIORef, writeIORef)
import qualified Data.Text.Encoding as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import Import.Fit.Decode (maxFitBytes)
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Internal (ResponseReceived (..))

-- Request IDs and generic errors never echo credentials or health payloads.
withRequest :: Environment -> (RequestContext -> Application) -> Application
withRequest environment route original respond = do
    rid <- UUID.toText <$> UUIDv4.nextRandom
    let context = RequestContext original rid
        isFitUpload = requestMethod original == methodPost && pathInfo original == ["api", "v1", "imports", "fit"]
        limit
            | take 3 (pathInfo original) == ["api", "v1", "auth"] = 16384
            | pathInfo original == ["api", "v1", "imports", "fit"] = maxFitBytes
            | otherwise = maxJsonBytes (settings environment)
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
    phase <- newIORef Diagnostics.BodyBuffer
    let handle = do
            body <- readLimited limit original
            case body of
                Nothing -> pure (failure status413 "payload_too_large" "Request body is too large")
                Just bytes -> do
                    writeIORef phase Diagnostics.Handler
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
    outcome <-
        try $
            if isFitUpload
                then do
                    admitted <- withAdmission (fitUploads environment) handle
                    pure $ case admitted of
                        Just response -> response
                        Nothing ->
                            mapResponseHeaders
                                (("Retry-After", "1") :)
                                (failure status429 "rate_limited" "Upload capacity is busy; retry shortly")
                else handle
    case outcome of
        Right response -> finish response
        Left err -> case fromException err :: Maybe SomeAsyncException of
            Just _ -> throwIO (err :: SomeException)
            Nothing -> do
                failedPhase <- readIORef phase
                let category = case fromException err :: Maybe IOException of
                        Just _ -> Diagnostics.IOFailure
                        Nothing -> Diagnostics.UnexpectedException
                Diagnostics.logFailure context failedPhase category
                finish (failure status500 "internal_error" "Request failed")

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
