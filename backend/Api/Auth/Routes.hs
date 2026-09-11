{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Auth.Routes (PublicAuthAPI, PrivateAuthAPI) where

import Api.Auth.Types
import Api.Common.Routes
import Api.Common.Types
import Data.Text (Text)
import Servant

type PublicAuthAPI =
    "auth"
        :> ( "policy"
                :> Summary "Read deployment authentication and upload policy"
                :> Response 'GET 200 AuthPolicy
                :<|> "web"
                    :> "csrf"
                    :> Summary "Obtain a CSRF token and establish or reuse the browser session"
                    :> Response 'GET 200 (CookieResponse CsrfToken)
                :<|> "web"
                    :> "login"
                    :> Summary "Create a browser session and rotate the CSRF token"
                    :> Header' '[Required, Strict] "X-CSRF-Token" Text
                    :> ReqBody '[JSON] Credentials
                    :> Response 'POST 200 (CookieResponse WebSession)
                :<|> "native"
                    :> "login"
                    :> Summary "Create a native session and return its opaque bearer token once"
                    :> ReqBody '[JSON] Credentials
                    :> Response 'POST 200 NativeSession
                :<|> "register"
                    :> Summary "Register an account when registration is enabled; login separately"
                    :> Header' '[Required, Strict] "X-CSRF-Token" Text
                    :> ReqBody '[JSON] Registration
                    :> Response 'POST 201 User
           )

type PrivateAuthAPI =
    "me" :> Summary "Read the authenticated user" :> Response 'GET 200 User
        :<|> "auth"
            :> "logout"
            :> Summary "Revoke the current session and clear the browser cookie"
            :> Response 'POST 204 (CookieResponse NoContent)
        :<|> "auth" :> "sessions" :> Pagination (Response 'GET 200 (Page Session))
        :<|> "auth"
            :> "sessions"
            :> Capture "sessionId" (Id "Session")
            :> Summary "Revoke an owned session"
            :> Response 'DELETE 204 NoContent
        :<|> "auth"
            :> "sessions"
            :> Summary "Revoke all sessions including the current session"
            :> Response 'DELETE 204 (CookieResponse NoContent)
        :<|> "auth"
            :> "password"
            :> Summary "Verify the current password, change it and revoke every session"
            :> ReqBody '[JSON] PasswordChange
            :> Response 'PUT 204 (CookieResponse NoContent)
