{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Import.Routes (ImportAPI) where

import Api.Binary (FitFile)
import Api.Common.Routes
import Api.Common.Types
import Api.Import.Types
import Servant

type ImportAPI =
    "imports"
        :> ( Pagination (Response 'GET 200 (Page ImportRecord))
                :<|> "fit"
                    :> Summary
                        "Import one FIT file; the server hashes actual bytes and deduplicates within the current user"
                    :> ReqBody '[OctetStream] FitFile
                    :> Response 'POST 200 ImportRecord
                :<|> "healthkit"
                    :> Summary "Submit a normalized HealthKit object; acknowledge only after durable commit"
                    :> ReqBody '[JSON] HealthKitSubmission
                    :> Response 'POST 200 ImportRecord
                :<|> Capture "importId" (Id "Import")
                    :> ( Response 'GET 200 ImportRecord
                            :<|> "retry"
                                :> Summary "Retry a failed unpublished FIT import from its retained archive"
                                :> ReqBody '[JSON] RevisionRequest
                                :> Response 'POST 200 ImportRecord
                            :<|> "refresh"
                                :> Summary
                                    "Reparse archived FIT data with explicit import and workout revisions; preserve user metadata"
                                :> ReqBody '[JSON] RefreshImport
                                :> Response 'POST 200 ImportRecord
                            :<|> "archive"
                                :> Summary "Remove archived bytes while retaining canonical data and the import index"
                                :> ExpectedRevision (Response 'DELETE 200 ImportRecord)
                            :<|> "suppression"
                                :> Summary "Explicitly allow this source to be imported again"
                                :> ExpectedRevision (Response 'DELETE 200 ImportRecord)
                            :<|> Summary
                                    "Suppress the source, remove its archive and optionally delete its published workouts atomically"
                                :> ExpectedRevision
                                    ( QueryParam' '[Required, Strict] "deleteWorkouts" Bool
                                        :> QueryParam' '[Required, Strict] "deleteEmptyGroups" Bool
                                        :> Response 'DELETE 204 NoContent
                                    )
                       )
           )
