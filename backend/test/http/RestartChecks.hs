{-# LANGUAGE OverloadedStrings #-}

module RestartChecks (prepare, verify) where

import Api.Auth.Types (NativeSession (..))
import Api.Common.Types (Id (..))
import Api.Workout.Types (ManualWorkout (..))
import App.Types (Environment)
import Control.Monad (void)
import Data.Aeson (eitherDecode, encode)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import qualified Fixtures as F
import HttpSupport
import Workout.Types

-- State lives only inside the private temporary test directory, never in logs
-- or the checkout. It contains synthetic credentials for the disposable DB.
prepare :: Environment -> FilePath -> IO ()
prepare env path = do
    registerUser env "restart.alice"
    NativeSession _ _ token <- loginNative env "restart.alice" testPassword
    submission <- Id <$> UUID.nextRandom
    let request = ManualWorkout submission (workoutObservation F.runningWorkout) (workoutUserData F.runningWorkout)
    workout <- call env "POST" "/api/v1/workouts" (bearer token) request 200 >>= decoded
    LBS.writeFile path (encode (token, request, workout :: Workout))

verify :: Environment -> FilePath -> IO ()
verify env path = do
    (token, request, original) <-
        LBS.readFile path >>= either (const (fail "Invalid restart test state")) pure . eitherDecode
    void (rawCall env "GET" "/api/v1/me" (bearer token) "" 200)
    let WorkoutId wid = workoutId original
    current <-
        rawCall env "GET" ("/api/v1/workouts/" <> Text.encodeUtf8 (UUID.toText wid)) (bearer token) "" 200
            >>= decoded
    assert "Canonical content survives process and database restart" (current == original)
    retried <-
        call env "POST" "/api/v1/workouts" (bearer token) (request :: ManualWorkout) 200 >>= decoded
    assert "Submission identity survives process and database restart" (retried == original)
    putStrLn
        "HTTP credentials, canonical data and submission identity survive process and PostgreSQL restart"
