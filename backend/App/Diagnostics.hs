{-# LANGUAGE OverloadedStrings #-}

module App.Diagnostics (Phase (..), FailureCategory (..), diagnostic, logFailure) where

import App.Types (RequestContext (..))
import Control.Exception (IOException, try)
import Data.Aeson (Value, encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.Text (Text)
import Network.Wai (pathInfo)
import System.IO (stderr)

data Phase = BodyBuffer | Handler | Storage

data FailureCategory
    = UnexpectedException
    | IOFailure
    | DatabaseFailure
    | CorruptWorkout
    | CorruptImport
    | CorruptExportReceipt

-- Closed categories and route families only: no raw paths, identifiers from the
-- request, headers, SQL, exception messages or health data enter diagnostics.
diagnostic :: RequestContext -> Phase -> FailureCategory -> Value
diagnostic context phase category =
    object
        [ "requestId" .= requestId context
        , "operation" .= operation
        , "phase" .= phaseName
        , "category" .= categoryName
        ]
  where
    operation :: Text
    operation = case pathInfo (request context) of
        ["api", "v1", "imports", "fit"] -> "fit_upload"
        "api" : "v1" : "auth" : _ -> "auth"
        "api" : "v1" : "workouts" : _ -> "workout"
        "api" : "v1" : "imports" : _ -> "import"
        "api" : "v1" : "exports" : _ -> "export"
        _ -> "other"
    phaseName :: Text
    phaseName = case phase of
        BodyBuffer -> "body_buffer"
        Handler -> "handler"
        Storage -> "storage"
    categoryName :: Text
    categoryName = case category of
        UnexpectedException -> "unexpected_exception"
        IOFailure -> "io_failure"
        DatabaseFailure -> "database_failure"
        CorruptWorkout -> "corrupt_workout"
        CorruptImport -> "corrupt_import"
        CorruptExportReceipt -> "corrupt_export_receipt"

logFailure :: RequestContext -> Phase -> FailureCategory -> IO ()
logFailure context phase category = do
    -- An unavailable stderr must not replace the original response. Async
    -- cancellation is deliberately not caught here.
    _ <-
        try (LBS.hPutStrLn stderr (encode (diagnostic context phase category)))
            :: IO (Either IOException ())
    pure ()
