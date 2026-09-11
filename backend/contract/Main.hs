module Main (main) where

import Api.OpenApi (openApi)
import Data.Aeson (encode)
import qualified Data.ByteString.Lazy.Char8 as ByteString

main :: IO ()
main = ByteString.putStrLn (encode openApi)
