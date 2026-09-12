{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module ExportChecks (checks, verifyRestart) where

import Api.Auth.Types (NativeSession (..))
import Api.Common.Types (Id (..), Page (..))
import qualified Api.Export.Types as Api
import qualified Api.Import.Types as Import
import qualified Api.Workout.Types as WorkoutApi
import App.Types (Environment (..))
import Control.Concurrent.Async (concurrently)
import Control.Monad (void)
import Data.ByteString (ByteString)
import Data.List (sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (isNothing)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.UUID.Types as UUID
import qualified Data.UUID.V4 as UUID
import qualified Data.Vector as V
import qualified Fixtures as F
import HttpSupport
import Web.HttpApiData (toUrlPiece)
import Workout.Empty (emptyUserData)
import Workout.Types

checks :: Environment -> IO ()
checks env = do
    registerUser env "export.alice"
    registerUser env "export.bob"
    NativeSession _ _ token <- loginNative env "export.alice" testPassword
    NativeSession _ _ other <- loginNative env "export.bob" testPassword
    first <- create token
    second <- create token
    let wid = workoutId first
        request = Api.RecordExport (WorkoutRevision 1) Api.AppleHealth (UUID.toText object1)
        path = receiptPath wid
    -- The platform may finish an older revision just before a backend edit.
    void
        ( call
            env
            "PUT"
            (workoutPath wid <> "/user-data")
            (bearer token)
            (WorkoutApi.EditWorkout (WorkoutRevision 1) emptyUserData {workoutTitle = Just "Edited"})
            200
        )
    now <- currentTime env
    let fixed = env {currentTime = pure now}
        record :: Text.Text -> WorkoutId -> Api.RecordExport -> IO Api.ExportReceipt
        record credential target body = call fixed "POST" (receiptPath target) (bearer credential) body 200 >>= decoded
    void (call fixed "POST" path [] request 401)
    (one, duplicate) <- concurrently (record token wid request) (record token wid request)
    assert "Concurrent export receipt retry preserves identity" (one == duplicate)
    assert
        "Receipt records the exported revision without overwriting current data"
        (receiptRevision one == WorkoutRevision 1)
    uppercase <-
        record
            token
            wid
            (Api.RecordExport (WorkoutRevision 1) Api.AppleHealth (Text.toUpper (UUID.toText object1)))
    assert "HealthKit UUID casing cannot bypass receipt identity" (uppercase == one)
    void (call fixed "POST" path (bearer other) request 404)
    void (rawCall fixed "GET" path (bearer other) "" 404)
    void (call fixed "POST" (receiptPath (workoutId second)) (bearer token) request 409)
    void
        ( call
            fixed
            "POST"
            path
            (bearer token)
            (Api.RecordExport (WorkoutRevision 2) Api.AppleHealth (UUID.toText object1))
            409
        )
    void
        ( call
            fixed
            "POST"
            path
            (bearer token)
            (Api.RecordExport (WorkoutRevision 3) Api.AppleHealth (UUID.toText object2))
            409
        )
    void
        ( call
            fixed
            "POST"
            path
            (bearer token)
            (Api.RecordExport (WorkoutRevision 1) Api.AppleHealth "not-an-object-uuid")
            422
        )
    two <- record token wid (Api.RecordExport (WorkoutRevision 2) Api.AppleHealth (UUID.toText object2))
    Page firstPage next <- rawCall fixed "GET" (path <> "?limit=1") (bearer token) "" 200 >>= decoded
    cursor <- maybe (fail "Expected a receipt cursor") pure next
    Page secondPage end <-
        rawCall fixed "GET" (path <> "?limit=1&cursor=" <> Text.encodeUtf8 cursor) (bearer token) "" 200
            >>= decoded
    assert
        "Receipt cursor handles tied timestamps without duplicates"
        ( V.length firstPage == 1
            && V.length secondPage == 1
            && isNothing end
            && sort (receiptID <$> V.toList (firstPage <> secondPage)) == sort [receiptID one, receiptID two]
        )
    void
        ( rawCall
            fixed
            "GET"
            (receiptPath (workoutId second) <> "?cursor=" <> Text.encodeUtf8 cursor)
            (bearer token)
            ""
            400
        )
    bobImport <- importObject other object1
    assert "Export origin filtering is owner scoped" (importStatus bobImport == Import.Succeeded)
    blocked <- importObject token object1
    assert "Export receipt prevents import feedback" (importStatus blocked == Import.Suppressed)
    void (record token wid (Api.RecordExport (WorkoutRevision 2) Api.AppleHealth (UUID.toText object3)))
    void
        ( rawCall
            env
            "DELETE"
            (workoutPath wid <> "?expectedRevision=2&deleteEmptyGroups=false")
            (bearer token)
            ""
            204
        )
    void (rawCall env "GET" path (bearer token) "" 404)
    blockedAfterDeletion <- importObject token object2
    assert
        "Receipt source identity survives canonical deletion"
        (importStatus blockedAfterDeletion == Import.Suppressed)
    putStrLn "Export receipt ownership, retry, exact pagination and loop prevention checks passed"
  where
    create token = do
        submission <- Id <$> UUID.nextRandom
        call
            env
            "POST"
            "/api/v1/workouts"
            (bearer token)
            (WorkoutApi.ManualWorkout submission F.observation emptyUserData)
            200
            >>= decoded
    importObject token object =
        call
            env
            "POST"
            "/api/v1/imports/healthkit"
            (bearer token)
            ( Import.HealthKitSubmission
                (Id object)
                Import.Normal
                Nothing
                []
                (Import.ImportPart "workout" F.observation emptyUserData :| [])
            )
            200
            >>= decoded

verifyRestart :: Environment -> IO ()
verifyRestart env = do
    NativeSession _ _ token <- loginNative env "export.alice" testPassword
    blocked <-
        call
            env
            "POST"
            "/api/v1/imports/healthkit"
            (bearer token)
            ( Import.HealthKitSubmission
                (Id object3)
                Import.Normal
                Nothing
                []
                (Import.ImportPart "workout" F.observation emptyUserData :| [])
            )
            200
            >>= decoded
    assert
        "Export-origin tombstone survives process and database restart"
        (importStatus blocked == Import.Suppressed)

object1, object2, object3 :: UUID.UUID
object1 = UUID.fromWords 0 0 0 201
object2 = UUID.fromWords 0 0 0 202
object3 = UUID.fromWords 0 0 0 203

receiptID :: Api.ExportReceipt -> Id "ExportReceipt"
receiptID (Api.ExportReceipt iid _ _ _ _ _) = iid

receiptRevision :: Api.ExportReceipt -> WorkoutRevision
receiptRevision (Api.ExportReceipt _ _ revision _ _ _) = revision

importStatus :: Import.ImportRecord -> Import.ImportStatus
importStatus (Import.ImportRecord _ _ _ status _ _ _ _ _) = status

workoutPath :: WorkoutId -> ByteString
workoutPath wid = "/api/v1/workouts/" <> Text.encodeUtf8 (toUrlPiece wid)

receiptPath :: WorkoutId -> ByteString
receiptPath wid = workoutPath wid <> "/export-receipts"
