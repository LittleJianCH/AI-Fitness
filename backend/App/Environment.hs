{-# LANGUAGE OverloadedStrings #-}

module App.Environment (loadSettings, withEnvironment, createEnvironment) where

import App.Types
import qualified Auth.Password as Password
import qualified Auth.Token as Token
import Control.Concurrent.MVar (newMVar)
import Control.Concurrent.QSem (newQSem)
import Control.Exception (bracket, evaluate)
import Control.Monad (unless)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Data.Time (getCurrentTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import qualified Hasql.Connection.Settings as Connection
import qualified Hasql.Pool as Pool
import qualified Hasql.Pool.Config as Pool
import qualified Hasql.Session as Session
import Network.URI (URI (..), URIAuth (..), parseURI)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

loadSettings :: IO Settings
loadSettings = do
    origin <- Text.pack <$> env "APP_ORIGIN" "https://localhost:5173"
    open <- env "REGISTRATION_OPEN" "false"
    memory <- number "ARGON_MEMORY_KIB" 65536
    iterations <- number "ARGON_ITERATIONS" 3
    config <- maybe (fail "Invalid Argon2 cost settings") pure (Password.options memory iterations)
    unless (open `elem` ["true", "false"]) $ fail "REGISTRATION_OPEN must be true or false"
    unless (validOrigin origin) $ fail "APP_ORIGIN must be an HTTPS origin without a trailing slash"
    bi <- number "BROWSER_IDLE_SECONDS" 1800
    ba <- number "BROWSER_ABSOLUTE_SECONDS" 43200
    ni <- number "NATIVE_IDLE_SECONDS" 604800
    na <- number "NATIVE_ABSOLUTE_SECONDS" 2592000
    if all (> 0) [bi, ba, ni, na] && bi <= ba && ni <= na && max ba na <= (31536000 :: Int)
        then
            pure
                ( Settings
                    (Text.encodeUtf8 origin)
                    (open == "true")
                    config
                    (fromIntegral bi)
                    (fromIntegral ba)
                    (fromIntegral ni)
                    (fromIntegral na)
                    30
                    60
                    (16 * 1024 * 1024)
                )
        else fail "Invalid session lifetime settings"
  where
    env key fallback = fromMaybe fallback <$> lookupEnv key
    number :: String -> Int -> IO Int
    number key fallback = env key (show fallback) >>= maybe (fail ("Invalid " <> key)) pure . readMaybe

withEnvironment :: Text -> Settings -> (Environment -> IO a) -> IO a
withEnvironment url config action = bracket acquire Pool.release $ \pool -> do
    result <- Pool.use pool (Session.script "SELECT 1")
    either (const (fail "Database connection failed")) pure result
    createEnvironment config pool >>= action
  where
    acquire =
        Pool.acquire $
            Pool.settings
                [ Pool.staticConnectionSettings (Connection.connectionString url)
                , Pool.initSession (Session.script "SET TIME ZONE 'UTC'")
                , Pool.size 10
                , Pool.acquisitionTimeout 10
                ]

validOrigin :: Text -> Bool
validOrigin value = case parseURI (Text.unpack value) of
    Just uri ->
        uriScheme uri == "https:"
            && null (uriPath uri)
            && null (uriQuery uri)
            && null (uriFragment uri)
            && case uriAuthority uri of
                Just authority ->
                    null (uriUserInfo authority)
                        && not (null (uriRegName authority))
                        && ( null (uriPort authority) || case readMaybe (drop 1 (uriPort authority)) of
                                Just port -> port > (0 :: Int) && port <= 65535
                                Nothing -> False
                           )
                Nothing -> False
    Nothing -> False

createEnvironment :: Settings -> Pool.Pool -> IO Environment
createEnvironment config pool = do
    dummy <- Token.newToken >>= Password.hashPassword (passwordOptions config) >>= evaluate
    workers <- newQSem 2
    key <- Text.encodeUtf8 <$> Token.newToken
    rate <- newMVar Map.empty
    imports <- newMVar Map.empty
    let now = do
            time <- getCurrentTime
            pure (posixSecondsToUTCTime (fromInteger (floor (utcTimeToPOSIXSeconds time * 1000000)) / 1000000))
    pure (Environment config pool now dummy workers key rate imports)
