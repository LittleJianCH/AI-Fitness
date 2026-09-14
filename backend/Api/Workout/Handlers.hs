{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Api.Workout.Handlers (server) where

import Api.Auth.Types (Principal (..))
import Api.Common.Types (Id (..), Timestamp (..))
import Api.Error (problem)
import qualified Api.Pagination as Pagination
import Api.Workout.Routes (WorkoutAPI)
import qualified Api.Workout.Types as Api
import App.Types
import Auth.Session (owned)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (throwE)
import Data.Aeson (toJSON)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import qualified Data.UUID.Types as UUID
import qualified Data.UUID.V4 as UUIDv4
import qualified Data.Vector as V
import Servant
import qualified Storage.Codec as Storage
import Storage.Types (StorageError (WorkoutNotFound))
import Storage.User.Types (userId)
import qualified Storage.Workout as Workouts
import qualified Storage.Workout.Lifecycle as Lifecycle
import qualified Storage.Workout.Query as Query
import qualified Storage.Workout.Statistics as Statistics
import qualified Storage.Workout.Submission as Submission
import Storage.Workout.Types (WorkoutFilter (..))
import qualified Workout.PowerCurve.Calculate as PowerCurve
import Workout.Types

server :: Environment -> RequestContext -> Principal -> Server WorkoutAPI
server environment context principal = list :<|> create :<|> details
  where
    list from before sportFilter tagFilter group cursor limit = do
        unless (maybe True Storage.validText tagFilter) $
            problem context 400 "invalid_query" "Tag cannot contain U+0000"
        count <- Pagination.pageLimit context limit
        unless (fromMaybe True ((<) <$> from <*> before)) $
            problem context 400 "invalid_query" "from must precede before"
        let scope =
                toJSON ("workouts" :: Text, principalUserId principal, from, before, sportFilter, tagFilter, group)
            query = WorkoutFilter (unwrap <$> from) (unwrap <$> before) (sportName <$> sportFilter) tagFilter
        after <- Pagination.readCursor environment context scope cursor
        rows <- owned environment context principal $ \auth ->
            -- No group can be persisted in this slice; matching membership is
            -- empty until group persistence and handlers are added together.
            if isJust group
                then pure V.empty
                else Query.listWorkouts (userId (authenticatedUser auth)) query after (fromIntegral (count + 1))
        let position (Api.WorkoutCard (WorkoutId wid) _ range _ _) = (rangeStart range, wid)
        respond
            (WithStatus @200 (Pagination.page count (Pagination.writeCursor environment scope . position) rows))
    create (Api.ManualWorkout (Id submission) observation userData) = do
        unless (submission /= UUID.nil) $
            problem context 422 "validation_failed" "submissionId must not be nil"
        wid <- WorkoutId <$> liftIO UUIDv4.nextRandom
        now <- liftIO (currentTime environment)
        workout <- owned environment context principal $ \auth ->
            Submission.createManual
                now
                (userId (authenticatedUser auth))
                submission
                (Workout wid (WorkoutRevision 1) observation userData)
        respond (WithStatus @200 workout)
    details wid = get wid :<|> powerCurve wid :<|> edit wid :<|> delete wid
    get wid = do
        now <- liftIO (currentTime environment)
        workout <- owned environment context principal $ \auth ->
            Statistics.load now (userId (authenticatedUser auth)) wid
        respond (WithStatus @200 workout)
    powerCurve wid = do
        workout <- owned environment context principal $ \auth ->
            Workouts.loadWorkout (userId (authenticatedUser auth)) wid
                >>= maybe (throwE WorkoutNotFound) pure
        -- Calculate after the owned read releases its transaction/account lock.
        respond (WithStatus @200 (PowerCurve.calculate workout))
    edit wid (Api.EditWorkout expected userData) = do
        now <- liftIO (currentTime environment)
        workout <- owned environment context principal $ \auth -> do
            let uid = userId (authenticatedUser auth)
            Statistics.replaceUserData now uid wid expected userData
        respond (WithStatus @200 workout)
    delete wid expected _deleteEmptyGroups = do
        now <- liftIO (currentTime environment)
        owned environment context principal $ \auth ->
            Lifecycle.deleteWorkout (userId (authenticatedUser auth)) wid expected now
        respond (WithStatus @204 NoContent)
    unwrap (Timestamp value) = value
    sportName Api.Cycling = "cycling"
    sportName Api.Running = "running"
