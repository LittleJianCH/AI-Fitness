{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module SettingsChecks (checks) where

import Analysis.Fatigue.Request
import qualified Api
import Api.Analysis.Codec ()
import Api.Auth.Types (NativeSession (..))
import Api.Common.Types (Id (..))
import Api.Settings.Codec ()
import qualified Api.Workout.Types as Api
import App.Types (Environment)
import Control.Concurrent.Async (concurrently)
import Control.Monad (void)
import Data.Aeson (encode)
import qualified Data.Text as T
import qualified Data.Text.Encoding as Text
import Data.Time (UTCTime (..), addUTCTime, defaultTimeLocale, formatTime, utctDay)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import qualified Data.Vector as V
import qualified Fixtures as F
import HttpSupport
import Network.HTTP.Types (statusCode)
import Network.Wai (isSecure, requestHeaders, requestMethod)
import Network.Wai.Test (SRequest (..), defaultRequest, runSession, setPath, simpleStatus, srequest)
import Profile.Settings (emptySettings)
import Profile.Types
import Workout.Analysis.Types
import Workout.Empty (emptyUserData)
import Workout.Types

checks :: Environment -> IO ()
checks env = do
    registerUser env "settings.alice"
    registerUser env "settings.bob"
    NativeSession _ _ alice <- loginNative env "settings.alice" testPassword
    NativeSession _ _ bob <- loginNative env "settings.bob" testPassword
    void (rawCall env "GET" path [] "" 401)
    void (call env "PUT" path [] emptySettings 401)
    initial <- rawCall env "GET" path (bearer alice) "" 200 >>= decoded
    assert "Settings start with an empty profile" (initial == emptySettings)
    bid <- UUID.nextRandom
    eid <- UUID.nextRandom
    let profile =
            BodyProfile
                bid
                F.start
                (Just 70)
                (Just 1.75)
                (SportProfile (Just 250) (Just (HeartRateProfile 50 190 165 Exponent192)))
                (SportProfile Nothing Nothing)
        equipment = Equipment eid Bicycle "Synthetic road bike" (Just 8) False
        proposed = initial {settingsBodyProfiles = V.singleton profile, settingsEquipment = V.singleton equipment}
    saved <- call env "PUT" path (bearer alice) proposed 200 >>= decoded
    assert
        "Settings persist with server revision"
        (saved == proposed {settingsRevision = SettingsRevision 1})
    loaded <- rawCall env "GET" path (bearer alice) "" 200 >>= decoded
    assert "Settings round trip" (loaded == saved)
    other <- rawCall env "GET" path (bearer bob) "" 200 >>= decoded
    assert "Settings never cross account boundaries" (other == emptySettings)
    void (call env "PUT" path (bearer alice) proposed 409)
    let rewritten = saved {settingsBodyProfiles = V.singleton (profile {bodyMassKilograms = Just 90})}
    void (call env "PUT" path (bearer alice) rewritten 422)
    void (call env "PUT" path (bearer alice) (saved {settingsEquipment = V.empty}) 422)
    -- Both requests expect revision 1. A single account lock serializes them.
    let update = saved {settingsSoftware = SoftwareSettings DarkAppearance}
    (left, right) <- concurrently (putEither alice update) (putEither alice update)
    assert
        "Concurrent settings edits have exactly one winner"
        (left /= right && all (`elem` [200, 409]) [left, right])
    submission <- Id <$> UUID.nextRandom
    workout <-
        call
            env
            "POST"
            "/api/v1/workouts"
            (bearer alice)
            (Api.ManualWorkout submission F.observation emptyUserData)
            200
            >>= decoded @Workout
    let WorkoutId wid = workoutId workout
        analysisPath = "/api/v1/workouts/" <> Text.encodeUtf8 (UUID.toText wid) <> "/analysis"
    result <- rawCall env "GET" analysisPath (bearer alice) "" 200 >>= decoded @WorkoutAnalysis
    assert
        "Analysis identifies workout and settings revisions"
        ( analysisRevision result == workoutRevision workout
            && analysisSettingsRevision result == SettingsRevision 2
        )
    assert "Analysis exposes the applicable body profile" (analysisBodyProfile result == Just profile)
    void (rawCall env "GET" analysisPath [] "" 401)
    void (rawCall env "GET" analysisPath (bearer bob) "" 404)
    let midnight = UTCTime (utctDay F.start) 0
        day =
            CalendarDay
                (T.pack (formatTime defaultTimeLocale "%Y-%m-%d" midnight))
                midnight
                (addUTCTime 86400 midnight)
                True
        historyRequest = TrainingHistoryRequest (V.singleton day) True Nothing Nothing
        historyPath = "/api/v1/analysis/training-history"
    void (call env "POST" historyPath [] historyRequest 401)
    history <-
        call env "POST" historyPath (bearer alice) historyRequest 200 >>= decoded @TrainingHistory
    assert
        "History includes only current owner workouts"
        (sum (V.map trainingWorkoutCount (trainingDays history)) == 1)
    otherHistory <-
        call env "POST" historyPath (bearer bob) historyRequest 200 >>= decoded @TrainingHistory
    assert
        "Other owner's complete rest remains zero"
        (all ((== Just 0) . trainingTotalLoad) (trainingDays otherHistory))
    void (call env "POST" historyPath (bearer alice) (historyRequest {historyCalendar = V.empty}) 422)
    putStrLn "Settings persistence, revision races, profile history and analysis owner isolation passed"
  where
    path = "/api/v1/settings"
    -- This race can legitimately produce either status; rawCall asserts one.
    -- Invoke the actual application and check both envelopes in the main suite.
    putEither token value = do
        let request =
                (setPath defaultRequest path)
                    { requestMethod = "PUT"
                    , requestHeaders = ("Content-Type", "application/json") : bearer token
                    , isSecure = True
                    }
        result <- runSession (srequest (SRequest request (encode value))) (Api.application env)
        pure (statusCode (simpleStatus result))
