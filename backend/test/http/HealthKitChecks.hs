{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module HealthKitChecks (checks, verifyRestart) where

import Api.Auth.Types (NativeSession (..))
import Api.Common.Types (Id (..), Revision (..))
import qualified Api.Import.Types as Api
import qualified Api.Workout.Types as WorkoutApi
import App.Types (Environment (..), Settings (..))
import Control.Concurrent.Async (concurrently)
import Control.Concurrent.MVar (newMVar)
import Control.Monad (void)
import Data.ByteString (ByteString)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import qualified Data.Text.Encoding as Text
import Data.Time (addUTCTime)
import qualified Data.UUID.Types as UUID
import qualified Data.UUID.V4 as UUID
import qualified Data.Vector as V
import qualified Fixtures as F
import HttpSupport
import Network.Wai.Test (simpleHeaders)
import Web.HttpApiData (toUrlPiece)
import Workout.Empty (emptyUserData)
import Workout.Types

checks :: Environment -> IO ()
checks env = do
    registerUser env "healthkit.alice"
    registerUser env "healthkit.bob"
    NativeSession _ _ token <- loginNative env "healthkit.alice" testPassword
    NativeSession _ _ other <- loginNative env "healthkit.bob" testPassword
    let part = Api.ImportPart "workout" F.observation emptyUserData
        request = Api.HealthKitSubmission source Api.Normal Nothing [] (part :| [])
        post credential value = call env "POST" "/api/v1/imports/healthkit" (bearer credential) value 200 >>= decoded
        get credential wid = rawCall env "GET" (workoutPath wid) (bearer credential) "" 200 >>= decoded
    void (call env "POST" "/api/v1/imports/healthkit" [] request 401)
    (first, duplicate) <- concurrently (post token request) (post token request)
    assert
        "Concurrent HealthKit requests publish once"
        (first == duplicate && status first == Api.Succeeded)
    let wid = publishedWorkout first
    initial <- get token wid
    assert "HealthKit preserves canonical observation" (workoutObservation initial == F.observation)
    otherImport <- post other request
    assert "Source identity is owner-scoped" (publishedWorkout otherImport /= wid)
    void (rawCall env "GET" (importPath first) (bearer other) "" 404)
    void (rawCall env "GET" (workoutPath wid) (bearer other) "" 404)
    loaded <- rawCall env "GET" (importPath first) (bearer token) "" 200 >>= decoded
    assert "Import acknowledgement is durably readable" (loaded == first)
    let userData = emptyUserData {workoutTitle = Just "Keep my title", workoutTags = V.singleton "owned"}
    edited <-
        call
            env
            "PUT"
            (workoutPath wid <> "/user-data")
            (bearer token)
            (WorkoutApi.EditWorkout (workoutRevision initial) userData)
            200
            >>= decoded
    let changedObservation =
            F.observation
                { observationAthlete = (observationAthlete F.observation) {athleteMass = Just (Mass 72)}
                }
        changedPart = Api.ImportPart "workout" changedObservation emptyUserData
        normalChanged = Api.HealthKitSubmission source Api.Normal Nothing [] (changedPart :| [])
    repeated <- post token normalChanged
    unchanged <- get token wid
    assert
        "Normal reimport does not replace observations or user edits"
        (repeated == first && unchanged == edited)
    let refresh =
            Api.HealthKitSubmission
                source
                Api.Refresh
                (Just (revision first))
                [Api.ExpectedWorkout wid (workoutRevision edited)]
                (changedPart :| [])
    refreshed <- post token refresh
    current <- get token wid
    assert
        "Explicit refresh retains identity and metadata"
        (publishedWorkout refreshed == wid && workoutUserData current == userData)
    assert
        "Explicit refresh updates only observation and revision"
        (workoutObservation current == changedObservation && workoutRevision current == WorkoutRevision 3)
    let changedKey =
            Api.HealthKitSubmission
                source
                Api.Refresh
                (Just (revision refreshed))
                [Api.ExpectedWorkout wid (workoutRevision current)]
                (Api.ImportPart "different-part" changedObservation emptyUserData :| [])
    void (call env "POST" "/api/v1/imports/healthkit" (bearer token) changedKey 409)
    -- A device cannot claim that its own calculated cache is trusted backend data.
    let withCalculated sport = case sport of
            Cycling cycling ->
                let summary = cyclingSummary cycling
                    calculation = Calculated (WorkoutRevision 1) "synthetic" "untrusted" F.start (recordedSummary summary)
                 in Cycling cycling {cyclingSummary = summary {calculatedSummary = Just calculation}}
            Running running ->
                let summary = runningSummary running
                    calculation = Calculated (WorkoutRevision 1) "synthetic" "untrusted" F.start (recordedSummary summary)
                 in Running running {runningSummary = summary {calculatedSummary = Just calculation}}
        claimed = F.observation {observationSport = withCalculated (observationSport F.observation)}
    void
        ( call
            env
            "POST"
            "/api/v1/imports/healthkit"
            (bearer token)
            ( Api.HealthKitSubmission
                source
                Api.Normal
                Nothing
                []
                (Api.ImportPart "workout" claimed emptyUserData :| [])
            )
            422
        )
    void (call env "POST" "/api/v1/imports/healthkit" (bearer token) refresh 409)
    let invalidObservation =
            changedObservation
                { observationRange =
                    TimeRange
                        (rangeEnd (observationRange changedObservation))
                        (rangeStart (observationRange changedObservation))
                }
        badPart = Api.ImportPart "workout" invalidObservation emptyUserData
        badRefresh =
            Api.HealthKitSubmission
                source
                Api.Refresh
                (Just (revision refreshed))
                [Api.ExpectedWorkout wid (workoutRevision current)]
                (badPart :| [])
    failed <- post token badRefresh
    afterFailure <- get token wid
    assert
        "Failed refresh preserves the published workout and mapping"
        (status failed == Api.Failed && publishedWorkout failed == wid && afterFailure == current)
    void
        ( call
            env
            "POST"
            "/api/v1/imports/healthkit"
            (bearer token)
            (Api.HealthKitSubmission source Api.Retry (Just (revision failed)) [] (changedPart :| []))
            409
        )
    normalFailed <- post token request
    assert "Normal request never retries a failed refresh" (normalFailed == failed)
    let recover =
            Api.HealthKitSubmission
                source
                Api.Refresh
                (Just (revision failed))
                [Api.ExpectedWorkout wid (workoutRevision current)]
                (changedPart :| [])
    recovered <- post token recover
    recoveredWorkout <- get token wid
    assert
        "Explicit refresh recovers the existing mapping"
        (status recovered == Api.Succeeded && publishedWorkout recovered == wid)
    -- Invalid combinations and multipart inputs cannot partially publish.
    void
        ( call
            env
            "POST"
            "/api/v1/imports/healthkit"
            (bearer token)
            (Api.HealthKitSubmission source Api.Normal (Just (Revision 1)) [] (part :| []))
            422
        )
    void
        ( call
            env
            "POST"
            "/api/v1/imports/healthkit"
            (bearer token)
            (Api.HealthKitSubmission source Api.Normal Nothing [] (part :| [part]))
            422
        )
    failedSource <- Id <$> UUID.nextRandom
    unpublished <-
        post token (Api.HealthKitSubmission failedSource Api.Normal Nothing [] (badPart :| []))
    assert
        "Invalid initial data commits only a failed acknowledgement"
        (status unpublished == Api.Failed && noOutput unpublished)
    let retry = Api.HealthKitSubmission failedSource Api.Retry (Just (revision unpublished)) [] (part :| [])
    retried <- post token retry
    assert "Revision-checked retry publishes failed initial import" (status retried == Api.Succeeded)
    -- Source deletion leaves a durable suppression tombstone.
    let deletion =
            workoutPath wid
                <> "?expectedRevision="
                <> Text.encodeUtf8 (toUrlPiece (workoutRevision recoveredWorkout))
                <> "&deleteEmptyGroups=false"
    void (rawCall env "DELETE" deletion (bearer other) "" 404)
    void (rawCall env "DELETE" deletion (bearer token) "" 204)
    suppressed <- post token request
    assert
        "Deletion suppresses source without losing historical mapping"
        (status suppressed == Api.Suppressed && publishedWorkout suppressed == wid)
    void (rawCall env "GET" (workoutPath wid) (bearer token) "" 404)
    windows <- newMVar Map.empty
    now <- currentTime env
    clock <- newIORef now
    let limited =
            env
                { settings = (settings env) {importRequestsPerMinute = 1}
                , importRateWindows = windows
                , currentTime = readIORef clock
                }
    void (call limited "POST" "/api/v1/imports/healthkit" (bearer token) request 200)
    throttled <- call limited "POST" "/api/v1/imports/healthkit" (bearer token) request 429
    assert
        "Import throttling provides Retry-After"
        (lookup "Retry-After" (simpleHeaders throttled) == Just "60")
    void (call limited "POST" "/api/v1/imports/healthkit" (bearer other) request 200)
    writeIORef clock (addUTCTime 61 now)
    void (call limited "POST" "/api/v1/imports/healthkit" (bearer token) request 200)
    putStrLn "HealthKit HTTP identity, refresh, retry, ownership and suppression checks passed"

verifyRestart :: Environment -> IO ()
verifyRestart env = do
    NativeSession _ _ token <- loginNative env "healthkit.alice" testPassword
    NativeSession _ _ other <- loginNative env "healthkit.bob" testPassword
    let request =
            Api.HealthKitSubmission
                source
                Api.Normal
                Nothing
                []
                (Api.ImportPart "workout" F.observation emptyUserData :| [])
    suppressed <- call env "POST" "/api/v1/imports/healthkit" (bearer token) request 200 >>= decoded
    succeeded <- call env "POST" "/api/v1/imports/healthkit" (bearer other) request 200 >>= decoded
    assert
        "HealthKit tombstone survives backend and database restart"
        (status suppressed == Api.Suppressed)
    assert
        "HealthKit published mapping survives backend and database restart"
        (status succeeded == Api.Succeeded)
    void (rawCall env "GET" (workoutPath (publishedWorkout succeeded)) (bearer other) "" 200)

source :: Id "HealthKitObject"
source = Id (UUID.fromWords 0 0 0 101)

status :: Api.ImportRecord -> Api.ImportStatus
status (Api.ImportRecord _ _ _ value _ _ _ _ _) = value

revision :: Api.ImportRecord -> Revision
revision (Api.ImportRecord _ value _ _ _ _ _ _ _) = value

publishedWorkout :: Api.ImportRecord -> WorkoutId
publishedWorkout
    ( Api.ImportRecord
            _
            _
            _
            _
            _
            _
            _
            (Just (Api.ImportOutput (Api.ImportedPart _ wid :| []) Nothing _ _))
            _
        ) = wid
publishedWorkout _ = error "Expected a single published synthetic workout"

noOutput :: Api.ImportRecord -> Bool
noOutput (Api.ImportRecord _ _ _ _ _ _ _ output _) = isNothing output

importPath :: Api.ImportRecord -> ByteString
importPath record = case record of
    Api.ImportRecord iid _ _ _ _ _ _ _ _ -> "/api/v1/imports/" <> Text.encodeUtf8 (toUrlPiece iid)

workoutPath :: WorkoutId -> ByteString
workoutPath wid = "/api/v1/workouts/" <> Text.encodeUtf8 (toUrlPiece wid)
