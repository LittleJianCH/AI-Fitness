{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Api.Export.Handlers (ReceiptAPI, server) where

import Api.Auth.Types (Principal (..))
import Api.Common.Types (Id (..), Timestamp (..))
import Api.Export.Routes (ExportReceiptsAPI)
import qualified Api.Export.Types as Api
import qualified Api.Pagination as Pagination
import App.Types
import Auth.Session (owned)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (toJSON)
import Data.Text (Text)
import qualified Data.UUID.V4 as UUID
import Servant
import qualified Storage.Export as Export
import Storage.User.Types (userId)
import Workout.Types (WorkoutId)

type ReceiptAPI = "workouts" :> Capture "workoutId" WorkoutId :> ExportReceiptsAPI

server :: Environment -> RequestContext -> Principal -> Server ReceiptAPI
server environment context principal wid = list :<|> record
  where
    list cursor limit = do
        count <- Pagination.pageLimit context limit
        let scope = toJSON ("export-receipts" :: Text, principalUserId principal, wid)
        after <- Pagination.readCursor environment context scope cursor
        rows <- owned environment context principal $ \auth ->
            Export.listReceipts (userId (authenticatedUser auth)) wid after (fromIntegral (count + 1))
        let position (Api.ExportReceipt (Id iid) _ _ _ _ (Timestamp at)) = (at, iid)
        respond
            (WithStatus @200 (Pagination.page count (Pagination.writeCursor environment scope . position) rows))
    record submission = do
        iid <- liftIO UUID.nextRandom
        now <- liftIO (currentTime environment)
        receipt <- owned environment context principal $ \auth ->
            Export.recordExport (userId (authenticatedUser auth)) wid iid now submission
        respond (WithStatus @200 receipt)
