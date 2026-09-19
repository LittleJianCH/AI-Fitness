{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Api (application) where

import qualified Api.Analysis.Handlers as Analysis
import Api.Analysis.Routes (AnalysisAPI)
import Api.Auth.Context (SessionAuth)
import qualified Api.Auth.Handlers as Auth
import Api.Auth.Routes (PrivateAuthAPI, PublicAuthAPI)
import Api.Auth.Types (Principal)
import Api.Boundary (withRequest)
import qualified Api.Error as Error
import qualified Api.Export.Handlers as Export
import qualified Api.Import.Handlers as Import
import qualified Api.Settings.Handlers as Settings
import Api.Settings.Routes (SettingsAPI)
import qualified Api.Workout.Handlers as Workout
import Api.Workout.Routes (WorkoutAPI)
import App.Types
import qualified Auth.Session as Session
import Data.Text (Text)
import Network.Wai (Request)
import Servant
import Servant.Server.Experimental.Auth (AuthHandler, mkAuthHandler)

-- Only implemented groups are mounted. Api.Types holds the full contract and
-- shares these aliases, without a second hand-maintained wire definition.
type RuntimeAPI =
    "api"
        :> "v1"
        :> ( "hello" :> Get '[PlainText] Text
                :<|> PublicAuthAPI
                :<|> AuthProtect SessionAuth
                    :> Header "X-CSRF-Token" Text
                    :> ( PrivateAuthAPI
                            :<|> WorkoutAPI
                            :<|> Import.RuntimeImportAPI
                            :<|> Export.ReceiptAPI
                            :<|> SettingsAPI
                            :<|> AnalysisAPI
                       )
           )

application :: Environment -> Application
application environment = withRequest environment $ \context ->
    let handlers =
            pure "hello world"
                :<|> Auth.publicServer environment context
                :<|> ( \principal _ ->
                        Auth.privateServer environment context principal
                            :<|> Workout.server environment context principal
                            :<|> Import.server environment context principal
                            :<|> Export.server environment context principal
                            :<|> Settings.server environment context principal
                            :<|> Analysis.server environment context principal
                     )
        auth :: AuthHandler Request Principal
        auth = mkAuthHandler (const (Session.authenticate environment context))
     in serveWithContext
            (Proxy :: Proxy RuntimeAPI)
            (auth :. Error.errorFormatters context :. EmptyContext)
            handlers
