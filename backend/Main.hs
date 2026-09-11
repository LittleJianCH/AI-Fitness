{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Api
import qualified App.Environment as App
import Config (config)
import qualified Data.Text as Text
import IHP.FrameworkConfig
    ( FrameworkConfig (appPort)
    , withFrameworkConfig
    )
import qualified Network.Wai.Handler.Warp as Warp
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = withFrameworkConfig config $ \frameworkConfig -> do
    databaseUrl <-
        lookupEnv "DATABASE_URL" >>= maybe (fail "DATABASE_URL is required") (pure . Text.pack)
    appSettings <- App.loadSettings
    let settings =
            Warp.setOnException (\_ _ -> hPutStrLn stderr "HTTP server request failed") $
                Warp.setHost "127.0.0.1" $
                    Warp.setPort frameworkConfig.appPort Warp.defaultSettings
    App.withEnvironment databaseUrl appSettings $ \environment ->
        Warp.runSettings settings (Api.application environment)
