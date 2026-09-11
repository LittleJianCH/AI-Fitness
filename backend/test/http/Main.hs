module Main (main) where

import qualified App.Environment as App
import App.Types
import qualified Auth.Password as Password
import qualified AuthChecks
import qualified AuthRaceChecks
import qualified Data.Text as Text
import System.Environment (getEnv)

main :: IO ()
main = do
    url <- Text.pack <$> getEnv "AI_FITNESS_TEST_DATABASE_URL"
    config <- App.loadSettings
    cost <- maybe (fail "Invalid test Argon2 cost") pure (Password.options 19456 2)
    let testConfig = config {registrationOpen = True, passwordOptions = cost, authRequestsPerMinute = 1000}
    App.withEnvironment url testConfig $ \environment -> do
        AuthChecks.checks environment
        AuthRaceChecks.checks environment
