{-# LANGUAGE OverloadedStrings #-}

module FitChecks (checks, verifyRestart) where

import Api.Auth.Types (AuthPolicy (..), Credentials (..), NativeSession (..), User (..))
import Api.Common.Types (Id (..))
import qualified Api.Import.Types as Api
import qualified Api.Workout.Types as WorkoutApi
import App.Types
import Control.Concurrent.Async (concurrently)
import Control.Monad (void)
import Data.Bits ((.&.))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (isNothing)
import qualified Data.Text
import qualified Data.Text.Encoding as Text
import qualified Data.UUID.Types as UUID
import HttpSupport
import Import.Fit.Decode (maxFitBytes)
import Network.Wai.Test (simpleHeaders)
import qualified Storage.Fit.Archive as Archive
import System.FilePath ((</>))
import System.Posix.Files (fileMode, getFileStatus)
import Web.HttpApiData (toUrlPiece)
import Workout.Empty (emptyUserData)
import Workout.Types

checks :: Environment -> IO ()
checks env = do
    registerUser env "fit.alice"
    registerUser env "fit.bob"
    NativeSession _ _ token <- loginNative env "fit.alice" testPassword
    NativeSession _ _ other <- loginNative env "fit.bob" testPassword
    bytes <- LBS.readFile "build/fit-fixtures-data/cycling.fit"
    let post credential input =
            rawCall
                env
                "POST"
                "/api/v1/imports/fit"
                (("Content-Type", "application/octet-stream") : bearer credential)
                input
                200
                >>= decoded
    policy <- rawCall env "GET" "/api/v1/auth/policy" [] "" 200 >>= decoded
    assert
        "Advertised FIT limit matches decoder"
        (case policy of AuthPolicy _ _ _ limit -> fromIntegral limit == maxFitBytes)
    void
        (rawCall env "POST" "/api/v1/imports/fit" [("Content-Type", "application/octet-stream")] bytes 401)
    void
        (rawCall env "POST" "/api/v1/imports/fit" (("Content-Type", "text/plain") : bearer token) bytes 400)
    void
        ( rawCall
            env
            "POST"
            "/api/v1/imports/fit"
            (("Content-Type", "application/octet-stream") : bearer token)
            (LBS.replicate (fromIntegral maxFitBytes + 1) 0)
            413
        )
    (first, duplicate) <- concurrently (post token bytes) (post token bytes)
    assert
        "Concurrent identical FIT publishes once"
        (first == duplicate && status first == Api.Succeeded)
    let wid = publishedWorkout first
    workout <- rawCall env "GET" (workoutPath wid) (bearer token) "" 200 >>= decoded
    assert
        "FIT canonical cycling observation"
        (case observationSport (workoutObservation workout) of Cycling _ -> True; _ -> False)
    edited <-
        call
            env
            "PUT"
            (workoutPath wid <> "/user-data")
            (bearer token)
            ( WorkoutApi.EditWorkout
                (workoutRevision workout)
                (emptyUserData {workoutTitle = Just "Keep FIT title"})
            )
            200
            >>= decoded
    again <- post token bytes
    after <- rawCall env "GET" (workoutPath wid) (bearer token) "" 200 >>= decoded
    assert
        "Normal FIT reupload preserves edits and revision"
        (again == first && after == (edited :: Workout))
    secondOwner <- post other bytes
    assert "FIT hash is scoped by owner" (publishedWorkout secondOwner /= wid)
    void (rawCall env "GET" (importPath first) (bearer other) "" 404)
    void (rawCall env "GET" (workoutPath wid) (bearer other) "" 404)
    NativeSession user _ _ <- loginNative env "fit.alice" testPassword
    -- Archive paths contain generated identities, never an uploaded filename.
    let owner = case user of User (Id value) _ _ -> value
        archive = fitArchiveRoot (settings env) </> UUID.toString owner </> showDigest bytes <> ".fit"
    retained <- LBS.readFile archive
    mode <- fileMode <$> getFileStatus archive
    assert "Exact FIT bytes are retained privately" (retained == bytes && mode .&. 0o077 == 0)
    invalid <- post token "invalid synthetic FIT"
    assert
        "Invalid FIT is a recorded failure, not a published workout"
        (status invalid == Api.Failed && noOutput invalid)
    repeatedInvalid <- post token "invalid synthetic FIT"
    assert "Normal failed reupload does not silently retry" (invalid == repeatedInvalid)
    unsupported <- LBS.readFile "build/fit-fixtures-data/swimming.fit" >>= post token
    assert
        "Unsupported FIT has no partial publication"
        (status unsupported == Api.Failed && noOutput unsupported)
    running <- LBS.readFile "build/fit-fixtures-data/running.fit"
    let brokenArchive = env {settings = (settings env) {fitArchiveRoot = archive}}
    void
        ( rawCall
            brokenArchive
            "POST"
            "/api/v1/imports/fit"
            (("Content-Type", "application/octet-stream") : bearer token)
            running
            500
        )
    recovered <- post token running
    assert
        "Archive IO failure leaves no committed failure or partial workout"
        (status recovered == Api.Succeeded)
    -- Browser mutations require a valid CSRF token and matching Origin.
    bootstrapSession <- bootstrap env
    logged <-
        call
            env
            "POST"
            "/api/v1/auth/web/login"
            (browserHeaders env bootstrapSession)
            (Credentials "fit.alice" testPassword Nothing)
            200
    cookie <- maybe (fail "Missing browser cookie") pure (lookup "Set-Cookie" (simpleHeaders logged))
    void
        ( rawCall
            env
            "POST"
            "/api/v1/imports/fit"
            [ ("Content-Type", "application/octet-stream")
            , ("Cookie", BS.takeWhile (/= 59) cookie)
            , ("Origin", allowedOrigin (settings env))
            ]
            bytes
            403
        )
    void
        ( rawCall
            env
            "DELETE"
            (workoutPath wid <> "?deleteEmptyGroups=false&expectedRevision=999")
            (bearer token)
            ""
            409
        )
    void
        ( rawCall
            env
            "DELETE"
            ( workoutPath wid
                <> "?deleteEmptyGroups=false&expectedRevision="
                <> Text.encodeUtf8 (toUrlPiece (workoutRevision edited))
            )
            (bearer token)
            ""
            204
        )
    suppressed <- post token bytes
    assert "Reupload preserves deletion tombstone" (status suppressed == Api.Suppressed)
    void (rawCall env "GET" (workoutPath wid) (bearer token) "" 404)
    -- Bob's live output and Alice's tombstone are checked after restart.
    putStrLn "FIT HTTP upload, deduplication, isolation, archive and suppression checks passed"

verifyRestart :: Environment -> IO ()
verifyRestart env = do
    NativeSession _ _ token <- loginNative env "fit.bob" testPassword
    NativeSession _ _ deleted <- loginNative env "fit.alice" testPassword
    bytes <- LBS.readFile "build/fit-fixtures-data/cycling.fit"
    let post credential =
            rawCall
                env
                "POST"
                "/api/v1/imports/fit"
                (("Content-Type", "application/octet-stream") : bearer credential)
                bytes
                200
                >>= decoded
    record <- post token
    void (rawCall env "GET" (workoutPath (publishedWorkout record)) (bearer token) "" 200)
    loaded <- rawCall env "GET" (importPath record) (bearer token) "" 200 >>= decoded
    assert
        "FIT import survives database and application restart"
        (loaded == record && status record == Api.Succeeded)
    tombstone <- post deleted
    assert "FIT suppression survives restart" (status tombstone == Api.Suppressed)
    putStrLn "FIT publication and suppression survive restart"

status :: Api.ImportRecord -> Api.ImportStatus
status (Api.ImportRecord _ _ _ value _ _ _ _ _) = value
noOutput :: Api.ImportRecord -> Bool
noOutput (Api.ImportRecord _ _ _ _ _ _ _ output _) = isNothing output
publishedWorkout :: Api.ImportRecord -> WorkoutId
publishedWorkout (Api.ImportRecord _ _ _ _ _ _ _ (Just (Api.ImportOutput (Api.ImportedPart _ wid :| []) _ _ _)) _) = wid
publishedWorkout _ = error "Expected one synthetic published workout"
workoutPath :: WorkoutId -> BS.ByteString
workoutPath wid = "/api/v1/workouts/" <> Text.encodeUtf8 (toUrlPiece wid)
importPath :: Api.ImportRecord -> BS.ByteString
importPath (Api.ImportRecord iid _ _ _ _ _ _ _ _) = "/api/v1/imports/" <> Text.encodeUtf8 (toUrlPiece iid)
showDigest :: LBS.ByteString -> String
showDigest = showText . Archive.digest . LBS.toStrict
  where
    showText = Data.Text.unpack
