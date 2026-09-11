{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Api
import Config (config)
import IHP.FrameworkConfig
    ( FrameworkConfig (appPort, requestLoggerMiddleware)
    , withFrameworkConfig
    )
import qualified Network.Wai.Handler.Warp as Warp

main :: IO ()
main = withFrameworkConfig config $ \frameworkConfig -> do
    let settings =
            Warp.setHost "127.0.0.1" $
                Warp.setPort frameworkConfig.appPort Warp.defaultSettings
    Warp.runSettings settings $
        frameworkConfig.requestLoggerMiddleware Api.application
