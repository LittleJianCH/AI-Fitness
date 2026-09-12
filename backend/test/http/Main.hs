module Main (main) where

import qualified App.Environment as App
import App.Types
import qualified Auth.Password as Password
import qualified AuthChecks
import qualified AuthRaceChecks
import qualified Data.Text as Text
import qualified ExportChecks
import qualified FitChecks
import qualified HealthKitChecks
import qualified InputChecks
import qualified RestartChecks
import System.Environment (getArgs, getEnv)
import qualified WorkoutChecks

main :: IO ()
main = do
    args <- getArgs
    url <- Text.pack <$> getEnv "AI_FITNESS_TEST_DATABASE_URL"
    config <- App.loadSettings
    cost <- maybe (fail "Invalid test Argon2 cost") pure (Password.options 19456 2)
    let testConfig = config {registrationOpen = True, passwordOptions = cost, authRequestsPerMinute = 1000}
    App.withEnvironment url testConfig $ \environment -> case args of
        ["verify-restart", path] -> do
            RestartChecks.verify environment path
            HealthKitChecks.verifyRestart environment
            ExportChecks.verifyRestart environment
            FitChecks.verifyRestart environment
        [path] -> do
            AuthChecks.checks environment
            AuthRaceChecks.checks environment
            InputChecks.checks environment
            WorkoutChecks.checks environment
            HealthKitChecks.checks environment
            ExportChecks.checks environment
            FitChecks.checks environment
            RestartChecks.prepare environment path
        _ -> fail "Expected a private restart-state path"
