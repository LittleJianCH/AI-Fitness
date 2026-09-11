{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}

module Api.Auth.Context (SessionAuth) where

import Api.Auth.Types (Principal)
import Servant (AuthProtect)
import Servant.Server.Experimental.Auth (AuthServerData)

data SessionAuth

type instance AuthServerData (AuthProtect SessionAuth) = Principal
