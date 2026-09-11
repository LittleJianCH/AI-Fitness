{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Types (API, ProtectedAPI) where

import Api.Auth.Context (SessionAuth)
import Api.Auth.Routes (PrivateAuthAPI, PublicAuthAPI)
import Api.Export.Routes (ExportAPI)
import Api.Import.Routes (ImportAPI)
import Api.Workout.Routes (WorkoutAPI)
import Api.WorkoutGroup.Routes (WorkoutGroupAPI)
import Data.Text (Text)
import Servant

-- Definitions for the product API. Api.application still serves only hello until
-- authentication, ownership checks and real handlers are implemented together.
type API =
    "api"
        :> "v1"
        :> ( PublicAuthAPI
                :<|> AuthProtect SessionAuth :> Header "X-CSRF-Token" Text :> ProtectedAPI
           )

type ProtectedAPI =
    PrivateAuthAPI :<|> WorkoutAPI :<|> WorkoutGroupAPI :<|> ImportAPI :<|> ExportAPI
