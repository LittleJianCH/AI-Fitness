{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Types (API, ProtectedAPI) where

import Api.Analysis.Routes (AnalysisAPI)
import Api.Auth.Context (SessionAuth)
import Api.Auth.Routes (PrivateAuthAPI, PublicAuthAPI)
import Api.Export.Routes (ExportAPI)
import Api.Import.Routes (ImportAPI)
import Api.Settings.Routes (SettingsAPI)
import Api.Workout.Routes (WorkoutAPI)
import Api.WorkoutGroup.Routes (WorkoutGroupAPI)
import Data.Text (Text)
import Servant

-- Complete product contract. Api.application mounts the implemented groups.
type API =
    "api"
        :> "v1"
        :> ( PublicAuthAPI
                :<|> AuthProtect SessionAuth :> Header "X-CSRF-Token" Text :> ProtectedAPI
           )

type ProtectedAPI =
    PrivateAuthAPI
        :<|> WorkoutAPI
        :<|> WorkoutGroupAPI
        :<|> ImportAPI
        :<|> ExportAPI
        :<|> SettingsAPI
        :<|> AnalysisAPI
