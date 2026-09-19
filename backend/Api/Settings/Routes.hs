{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Settings.Routes (SettingsAPI) where

import Api.Common.Routes (Response)
import Api.Settings.Codec ()
import Profile.Types (UserSettings)
import Servant

type SettingsAPI =
    "settings"
        :> ( Summary "Read software preferences, effective-dated body parameters and equipment"
                :> Response 'GET 200 UserSettings
                :<|> Summary "Replace settings using the current revision; body history is append-only"
                    :> ReqBody '[JSON] UserSettings
                    :> Response 'PUT 200 UserSettings
           )
