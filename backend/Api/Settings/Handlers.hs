{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

module Api.Settings.Handlers (server) where

import Api.Auth.Types (Principal)
import Api.Settings.Routes (SettingsAPI)
import App.Types
import Auth.Session (owned)
import Servant
import qualified Storage.Settings as Settings
import Storage.User.Types (userId)

server :: Environment -> RequestContext -> Principal -> Server SettingsAPI
server environment context principal = get :<|> put
  where
    get = do
        settings <- owned environment context principal $ \auth -> Settings.load (userId (authenticatedUser auth))
        respond (WithStatus @200 settings)
    put proposed = do
        settings <- owned environment context principal $ \auth -> Settings.save (userId (authenticatedUser auth)) proposed
        respond (WithStatus @200 settings)
