{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Api (application) where

import Data.Text (Text)
import Network.Wai (Application)
import Servant (Get, PlainText, Proxy (..), serve, (:>))

type HelloAPI = "api" :> "v1" :> "hello" :> Get '[PlainText] Text

application :: Application
application = serve (Proxy :: Proxy HelloAPI) (pure "hello world")
