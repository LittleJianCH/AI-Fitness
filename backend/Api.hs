{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Api (API, application) where

import Data.Text (Text)
import Network.Wai (Application)
import Servant (Get, PlainText, Proxy (..), (:>), serve)

type API = "api" :> "v1" :> "hello" :> Get '[PlainText] Text

application :: Application
application = serve (Proxy :: Proxy API) (pure "hello world")
