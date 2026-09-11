{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Export.Routes (ExportAPI) where

import Api.Binary (FitFile)
import Api.Common.Routes
import Api.Common.Types
import Api.Export.Types
import Data.Text (Text)
import Servant
import Workout.Identity.Types (WorkoutGroupId, WorkoutId)

type ExportAPI =
    "workouts"
        :> Capture "workoutId" WorkoutId
        :> ( "exports"
                :> "canonical"
                :> Summary "Export all supported canonical fields without reading a source archive"
                :> Response 'GET 200 CanonicalExport
                :<|> "exports"
                    :> "fit"
                    :> Summary "Export a FIT projection; unsupported canonical fields are not losslessly representable"
                    :> Get '[OctetStream] (Headers '[Header "Content-Disposition" Text] FitFile)
                :<|> "export-receipts"
                    :> Summary "List platform objects successfully exported from this workout"
                    :> Pagination (Response 'GET 200 (Page ExportReceipt))
                :<|> "export-receipts"
                    :> Summary "Record a successful platform write idempotently after the device commits it"
                    :> ReqBody '[JSON] RecordExport
                    :> Response 'POST 200 ExportReceipt
           )
        :<|> "workout-groups"
            :> Capture "groupId" WorkoutGroupId
            :> "exports"
            :> "canonical"
            :> Summary "Export the group and complete member workouts in group order"
            :> Response 'GET 200 CanonicalExport
