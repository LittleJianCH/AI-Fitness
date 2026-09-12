{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Api.Import.Handlers (HealthKitAPI, server) where

import Api.Auth.Types (Principal)
import Api.Common.Types (Id)
import Api.Import.Routes (HealthKitSubmissionAPI, ImportDetailAPI)
import App.Types
import Auth.Session (owned)
import Control.Monad.IO.Class (liftIO)
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
        iid <- liftIO UUID.nextRandom
        wid <- WorkoutId <$> liftIO UUID.nextRandom
        now <- liftIO (currentTime environment)
        record <- owned environment context principal $ \auth ->
            HealthKit.submit (userId (authenticatedUser auth)) iid wid now submission
        respond (WithStatus @200 record)
    get iid = do
        record <- owned environment context principal $ \auth -> HealthKit.loadImport (userId (authenticatedUser auth)) iid
        respond (WithStatus @200 record)
