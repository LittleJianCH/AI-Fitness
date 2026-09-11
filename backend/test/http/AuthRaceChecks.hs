{-# LANGUAGE OverloadedStrings #-}

module AuthRaceChecks (checks) where

import Api.Auth.Types (Credentials (..), NativeSession (..), PasswordChange (..))
import App.Types
import Control.Concurrent.Async (wait, withAsync)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Monad (void, when)
import Data.IORef (atomicModifyIORef', newIORef)
import Data.Text (Text)
import HttpSupport
import System.Timeout (timeout)

checks :: Environment -> IO ()
checks env = do
    registerUser env "race.revoke"
    NativeSession _ _ oldToken <- loginNative env "race.revoke" testPassword
    racedToken <-
        pauseClock
            env
            2
            (\paused -> void (rawCall paused "DELETE" "/api/v1/auth/sessions" (bearer oldToken) "" 204))
            (newLogin "race.revoke" testPassword)
    rejected oldToken
    rejected racedToken

    registerUser env "race.password"
    NativeSession _ _ passwordToken <- loginNative env "race.password" testPassword
    let changedPassword = "changed-password-race-123"
    duringChange <-
        pauseClock
            env
            4
            ( \paused ->
                void
                    ( call
                        paused
                        "PUT"
                        "/api/v1/auth/password"
                        (bearer passwordToken)
                        (PasswordChange testPassword changedPassword)
                        204
                    )
            )
            (newLogin "race.password" testPassword)
    rejected passwordToken
    rejected duringChange
    void (newLogin "race.password" changedPassword)

    -- A login that verified the old hash before a password change must recheck
    -- it under the account lock, even if its session was already prepared.
    registerUser env "race.login"
    NativeSession _ _ changingToken <- loginNative env "race.login" testPassword
    void $
        pauseClock
            env
            3
            ( \paused ->
                void
                    ( call
                        paused
                        "POST"
                        "/api/v1/auth/native/login"
                        []
                        (Credentials "race.login" testPassword Nothing)
                        401
                    )
            )
            ( call
                env
                "PUT"
                "/api/v1/auth/password"
                (bearer changingToken)
                (PasswordChange testPassword changedPassword)
                204
            )
    putStrLn "Concurrent login, revoke-all and password-change races passed"
  where
    rejected token = void (rawCall env "GET" "/api/v1/me" (bearer token) "" 401)
    newLogin :: Text -> Text -> IO Text
    newLogin name password = do
        NativeSession _ _ token <- loginNative env name password
        pure token

-- Pause immediately after a request's pre-lock time sample. The sampling points
-- are deliberately tied to these handler sequences, and bounded by a timeout
-- so a refactor cannot leave the suite hanging silently.
pauseClock :: Environment -> Int -> (Environment -> IO ()) -> IO a -> IO a
pauseClock env sample action concurrent = do
    result <- timeout 10000000 $ do
        count <- newIORef (0 :: Int)
        reached <- newEmptyMVar
        resume <- newEmptyMVar
        let clock = do
                now <- currentTime env
                ordinal <- atomicModifyIORef' count (\n -> (n + 1, n + 1))
                when (ordinal == sample) (putMVar reached () >> takeMVar resume)
                pure now
        withAsync (action (env {currentTime = clock})) $ \pending -> do
            takeMVar reached
            value <- concurrent
            putMVar resume ()
            wait pending
            pure value
    maybe (fail "Authentication race barrier timed out") pure result
