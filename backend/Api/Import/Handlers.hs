{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Api.Import.Handlers (RuntimeImportAPI, server) where

import Api.Auth.Types (Principal (..))
import Api.Binary (FitFile (..))
import Api.Common.Types (Id (..))
import Api.Error (problemError)
import Api.Import.Routes (FitUploadAPI, HealthKitSubmissionAPI, ImportDetailAPI)
import qualified Api.Import.Types as Import
import App.Types
import Auth.Session (owned)
import Control.Concurrent.MVar (modifyMVar)
import Control.Concurrent.QSem (signalQSem, waitQSem)
import Control.Exception (bracket_)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Bifunctor (first)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import Data.Time (diffUTCTime)
import qualified Data.UUID.V4 as UUID
import Import.Fit (FitError (..), parseFit)
import Servant
import qualified Storage.Fit as Fit
import qualified Storage.Fit.Archive as Archive
import qualified Storage.HealthKit as HealthKit
import Storage.User.Types (userId)
import Workout.Types (WorkoutId (..))

type RuntimeImportAPI =
    "imports"
        :> ( FitUploadAPI
                :<|> HealthKitSubmissionAPI
                :<|> Capture "importId" (Id "Import") :> ImportDetailAPI
           )

server :: Environment -> RequestContext -> Principal -> Server RuntimeImportAPI
server environment context principal = upload :<|> submit :<|> get
  where
    upload (FitFile input) = do
        rateLimitImport environment context principal
        let bytes = LBS.toStrict input
            sha = Archive.digest bytes
            Id owner = principalUserId principal
        existing <- owned environment context principal $ \auth ->
            Fit.findImport (userId (authenticatedUser auth)) sha
        let importNew = do
                result <- liftIO
                    $ bracket_
                        (waitQSem (fitWorkers environment))
                        (signalQSem (fitWorkers environment))
                    $ do
                        parsed <- parseFit bytes
                        Archive.retain (fitArchiveRoot (settings environment)) owner bytes
                        pure (first fitFailure parsed)
                iid <- liftIO UUID.nextRandom
                wid <- WorkoutId <$> liftIO UUID.nextRandom
                now <- liftIO (currentTime environment)
                owned environment context principal $ \auth ->
                    Fit.publish (userId (authenticatedUser auth)) iid wid sha now result
        record <- maybe importNew pure existing
        respond (WithStatus @200 record)
    submit submission = do
        rateLimitImport environment context principal
        iid <- liftIO UUID.nextRandom
        wid <- WorkoutId <$> liftIO UUID.nextRandom
        now <- liftIO (currentTime environment)
        record <- owned environment context principal $ \auth ->
            HealthKit.submit (userId (authenticatedUser auth)) iid wid now submission
        respond (WithStatus @200 record)
    get iid = do
        record <- owned environment context principal $ \auth -> do
            let uid = userId (authenticatedUser auth)
            fit <- Fit.loadImport uid iid
            maybe (HealthKit.loadImport uid iid) pure fit
        respond (WithStatus @200 record)

-- Authenticated owner buckets are independent of authentication throttling.
-- Bound total work and window cardinality as well as one account's requests.
rateLimitImport :: Environment -> RequestContext -> Principal -> Handler ()
rateLimitImport environment context principal = do
    now <- liftIO (currentTime environment)
    let Id owner = principalUserId principal
        limit = importRequestsPerMinute (settings environment)
    accepted <- liftIO $ modifyMVar (importRateWindows environment) $ \windows -> do
        let live = Map.filter (\(since, _) -> diffUTCTime now since < 60) windows
            (started, count) = Map.findWithDefault (now, 0) owner live
            total = sum (snd <$> Map.elems live)
            accept = count < limit && total < limit * 10 && Map.size live < 10000
        pure (if accept then Map.insert owner (started, count + 1) live else live, accept)
    unless accepted $
        throwError
            (problemError context 429 "rate_limited" "Too many import requests")
                { errHeaders = [("Content-Type", "application/json"), ("Retry-After", "60")]
                }

fitFailure :: FitError -> Import.Failure
fitFailure failure = case failure of
    InvalidFit -> Import.Failure "invalid_fit" "The file is not a valid FIT activity" False
    UnsupportedFit ->
        Import.Failure
            "unsupported_fit"
            "Only single-session cycling and running FIT activities are supported"
            False
    MissingFitTime ->
        Import.Failure
            "missing_fit_time"
            "The FIT activity has no supported absolute time range"
            False
    FitResourceLimit ->
        Import.Failure "fit_resource_limit" "The FIT activity exceeds parser resource limits" False
    InvalidFitObservation _ ->
        Import.Failure "validation_failed" "The FIT activity failed canonical validation" False
    FitAdapterFailure ->
        Import.Failure "fit_parser_failed" "The FIT parser could not process this activity" False
    FitFileUnreadable -> Import.Failure "fit_unreadable" "The FIT activity could not be read" False
