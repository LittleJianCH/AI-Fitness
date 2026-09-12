{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Api.Import.Handlers (HealthKitAPI, server) where

import Api.Auth.Types (Principal (..))
import Api.Common.Types (Id (..))
import Api.Error (problemError)
import Api.Import.Routes (HealthKitSubmissionAPI, ImportDetailAPI)
import App.Types
import Auth.Session (owned)
import Control.Concurrent.MVar (modifyMVar)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Map.Strict as Map
import Data.Time (diffUTCTime)
import qualified Data.UUID.V4 as UUID
import Servant
import qualified Storage.HealthKit as HealthKit
import Storage.User.Types (userId)
import Workout.Types (WorkoutId (..))

type HealthKitAPI =
    "imports" :> (HealthKitSubmissionAPI :<|> Capture "importId" (Id "Import") :> ImportDetailAPI)

server :: Environment -> RequestContext -> Principal -> Server HealthKitAPI
server environment context principal = submit :<|> get
  where
    submit submission = do
        rateLimitImport environment context principal
        iid <- liftIO UUID.nextRandom
        wid <- WorkoutId <$> liftIO UUID.nextRandom
        now <- liftIO (currentTime environment)
        record <- owned environment context principal $ \auth ->
            HealthKit.submit (userId (authenticatedUser auth)) iid wid now submission
        respond (WithStatus @200 record)
    get iid = do
        record <- owned environment context principal $ \auth -> HealthKit.loadImport (userId (authenticatedUser auth)) iid
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
