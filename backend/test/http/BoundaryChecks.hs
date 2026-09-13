{-# LANGUAGE OverloadedStrings #-}

module BoundaryChecks (checks) where

import Api.Boundary (withRequest)
import App.Admission (newAdmission)
import qualified App.Diagnostics as Diagnostics
import App.Types
import Control.Concurrent (forkFinally, killThread)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Concurrent.QSem (signalQSem, waitQSem)
import Control.Exception (bracket_, throwIO)
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString as BS
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import HttpSupport (assert)
import Import.Fit.Decode (maxFitBytes)
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Internal (ResponseReceived (..))
import System.Timeout (timeout)

checks :: Environment -> IO ()
checks original = do
    slots <- newAdmission 1
    let env = original {fitUploads = slots}
        fit =
            defaultRequest
                { requestMethod = methodPost
                , pathInfo = ["api", "v1", "imports", "fit"]
                , requestBodyLength = ChunkedBody
                }
        success _ _ respond = respond (responseLBS status204 [] "")
        run route req = do
            result <- newIORef Nothing
            _ <-
                withRequest env route req (\response -> writeIORef result (Just response) >> pure ResponseReceived)
            readIORef result >>= maybe (fail "Missing boundary response") pure
        expect label code response = assert label (statusCode (responseStatus response) == code)
        emptyFit = setRequestBodyChunks (pure BS.empty) fit
        available = run success emptyFit >>= expect "Upload permit released" 204
    entered <- newEmptyMVar
    blocked <- newEmptyMVar
    completed <- newEmptyMVar
    tid <-
        forkFinally
            (run success (setRequestBodyChunks (putMVar entered () >> takeMVar blocked) fit))
            (putMVar completed)
    within "First body began" (takeMVar entered)
    bodyReads <- newIORef (0 :: Int)
    busy <-
        within "Busy uploads reject without waiting" $
            run success (setRequestBodyChunks (modifyIORef' bodyReads (+ 1) >> pure BS.empty) fit)
    expect "Busy upload status" 429 busy
    assert
        "Retry-After on admission rejection"
        (lookup "Retry-After" (responseHeaders busy) == Just "1")
    readIORef bodyReads >>= assert "Rejected body was never read" . (== 0)
    run success (emptyFit {pathInfo = ["api", "v1", "workouts"]})
        >>= expect "Other routes are independent" 204
    killThread tid
    cancelled <- within "Cancelled request terminates" (takeMVar completed)
    assert "Cancellation propagates" $ case cancelled of
        Left _ -> True
        Right _ -> False
    available
    run (\_ _ _ -> throwIO (userError "synthetic-private-path-and-payload")) emptyFit
        >>= expect "Handler failure is generic" 500
    available
    run success (setRequestBodyChunks (throwIO (userError "synthetic-disconnect")) fit)
        >>= expect "Body failure is caught" 500
    available
    run success (emptyFit {requestBodyLength = KnownLength (fromIntegral maxFitBytes + 1)})
        >>= expect "Oversized body rejected" 413
    available
    -- One request holds the upload permit while obtaining a distinct parser
    -- permit. Reusing the same semaphore would deadlock at capacity one.
    within "Parser and upload permits are independent" $
        run
            ( \context req respond -> bracket_ (waitQSem (fitWorkers env)) (signalQSem (fitWorkers env)) (success context req respond)
            )
            emptyFit
            >>= expect "Independent parser succeeds" 204
    let context =
            RequestContext
                ( fit
                    { pathInfo = ["private-route", "synthetic-health-value"]
                    , requestHeaders = [(hAuthorization, "synthetic-token")]
                    }
                )
                "generated-request-id"
    assert "Diagnostics contain only approved fields" $
        encode (Diagnostics.diagnostic context Diagnostics.BodyBuffer Diagnostics.IOFailure)
            == encode
                ( object
                    [ "requestId" .= ("generated-request-id" :: String)
                    , "operation" .= ("other" :: String)
                    , "phase" .= ("body_buffer" :: String)
                    , "category" .= ("io_failure" :: String)
                    ]
                )

within :: String -> IO a -> IO a
within label action = timeout 5000000 action >>= maybe (fail label) pure
