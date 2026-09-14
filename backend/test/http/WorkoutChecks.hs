{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module WorkoutChecks (checks) where

import Api.Auth.Types (NativeSession (..), User (..))
import Api.Common.Types (Id (..), Page (..), Problem (..), Timestamp (..))
import qualified Api.Workout.Types as Api
import App.Types (Environment)
import Control.Concurrent.Async (concurrently)
import Control.Monad (void)
import Data.Aeson (Value (..), toJSON)
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.List (sortOn)
import Data.Maybe (isNothing)
import Data.Ord (Down (..))
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Data.Time (addUTCTime)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import qualified Data.Vector as V
import qualified Fixtures as F
import HttpSupport
import Network.Wai.Test (simpleBody, simpleHeaders)
import qualified Storage.User as Users
import qualified Storage.User.Types as U
import qualified Storage.Workout as Workouts
import Web.HttpApiData (toUrlPiece)
import Workout.Empty
import qualified Workout.PowerCurve.Calculate as PowerCurve
import qualified Workout.PowerCurve.Types as PC
import qualified Workout.Sport as Sport
import qualified Workout.Statistics as Statistics
import Workout.Types

checks :: Environment -> IO ()
checks env = do
    registerUser env "workout.alice"
    registerUser env "workout.bob"
    NativeSession alice _ token <- loginNative env "workout.alice" testPassword
    NativeSession _ _ bobToken <- loginNative env "workout.bob" testPassword
    submission <- Id <$> UUID.nextRandom
    let userData =
            emptyUserData {workoutTitle = Just "Synthetic ride", workoutTags = V.fromList ["commute", "test"]}
        request = Api.ManualWorkout submission F.observation userData
    void (call env "POST" "/api/v1/workouts" [] request 401)
    (first, duplicate) <- concurrently (create token request) (create token request)
    assert "Concurrent creation is idempotent" (first == duplicate)
    assert
        "Server generates identity"
        (workoutId first /= F.wid && workoutRevision first == WorkoutRevision 1)
    assert
        "Cycling preserves complete canonical content"
        (sourceObservation first == F.observation && workoutUserData first == userData)
    fetched <- getWorkout token (workoutId first)
    assert
        "Detail preserves sensor streams and reuses calculated cache"
        (fetched == first && Statistics.isCurrent first)
    void (rawCall env "GET" (workoutPath (workoutId first)) (bearer bobToken) "" 404)
    void
        ( call
            env
            "PUT"
            (workoutPath (workoutId first) <> "/user-data")
            (bearer bobToken)
            (Api.EditWorkout (WorkoutRevision 1) emptyUserData)
            404
        )
    let changed = userData {workoutNotes = Just "Edited", workoutTags = V.singleton "training"}
    edited <-
        call
            env
            "PUT"
            (workoutPath (workoutId first) <> "/user-data")
            (bearer token)
            (Api.EditWorkout (WorkoutRevision 1) changed)
            200
            >>= decoded
    assert
        "Editing increments revision and preserves observations"
        ( workoutRevision edited == WorkoutRevision 2
            && sourceObservation edited == sourceObservation first
            && Statistics.isCurrent edited
        )
    void
        ( call
            env
            "PUT"
            (workoutPath (workoutId first) <> "/user-data")
            (bearer token)
            (Api.EditWorkout (WorkoutRevision 1) userData)
            409
        )
    retried <- create token request
    assert "Retry returns current revision and edits" (retried == edited)
    void
        ( call
            env
            "POST"
            "/api/v1/workouts"
            (bearer token)
            (Api.ManualWorkout submission F.observation changed)
            409
        )
    -- Unknown JSON fields are ignored; they cannot select an owner.
    let User aliceId _ _ = alice
        forged = case toJSON request of
            Object fields -> Object (KM.insert "userId" (toJSON aliceId) fields)
            value -> value
    bobWorkout <- call env "POST" "/api/v1/workouts" (bearer bobToken) forged 200 >>= decoded
    assert "Submission identity is scoped to owner" (workoutId bobWorkout /= workoutId first)
    void (rawCall env "GET" (workoutPath (workoutId bobWorkout)) (bearer token) "" 404)
    runSubmission <- Id <$> UUID.nextRandom
    let runRequest = Api.ManualWorkout runSubmission (workoutObservation F.runningWorkout) emptyUserData
    running <- create token runRequest
    assert
        "Running preserves complete canonical content"
        (sourceObservation running == workoutObservation F.runningWorkout)
    -- An invalid first attempt must roll back the claim as well as the workout.
    retrySubmission <- Id <$> UUID.nextRandom
    let invalidObservation = F.observation {observationRange = TimeRange (F.at 100) F.start}
    invalid <-
        call
            env
            "POST"
            "/api/v1/workouts"
            (bearer token)
            (Api.ManualWorkout retrySubmission invalidObservation emptyUserData)
            422
            >>= decoded
    let Problem _ _ _ fields = invalid
    assert "Domain failures expose field paths" (not (null fields))
    repaired <- create token (Api.ManualWorkout retrySubmission F.observation emptyUserData)
    assert
        "Failed attempt does not reserve the submission ID"
        (workoutRevision repaired == WorkoutRevision 1)
    void
        ( call
            env
            "POST"
            "/api/v1/workouts"
            (bearer token)
            (Api.ManualWorkout (Id UUID.nil) F.observation emptyUserData)
            422
        )
    void
        ( call
            env
            "PUT"
            (workoutPath (workoutId repaired) <> "/user-data")
            (bearer token)
            (Api.EditWorkout (WorkoutRevision 0) emptyUserData)
            409
        )
    older <- tinyRun token (1 / 1000000000000)
    newer <- tinyRun token (2 / 1000000000000)
    Page allRows _ <- list token ""
    let positions = position <$> V.toList allRows
    assert "Exact time descending then UUID descending" (positions == sortOn Down positions)
    assert
        "Sub-microsecond start remains distinct"
        (take 2 (Api._id <$> V.toList allRows) == [workoutId newer, workoutId older])
    Page cycling _ <- list token "?sport=cycling"
    assert "Cycling filter" (V.length cycling == 2)
    Page runs _ <- list token "?sport=running"
    assert "Running filter" (V.length runs == 3)
    Page tagged _ <- list token "?tag=training"
    assert "Exact tag filter" (V.length tagged == 1)
    Page partialTag _ <- list token "?tag=train"
    assert "Tag does not match substrings" (V.null partialTag)
    let newerStart = rangeStart (observationRange (workoutObservation newer))
        olderStart = rangeStart (observationRange (workoutObservation older))
        timeParam = Text.encodeUtf8 . toUrlPiece . Timestamp
    Page fromRows _ <- list token ("?from=" <> timeParam newerStart)
    assert "from includes its boundary with full precision" (V.length fromRows == 1)
    Page beforeRows _ <- list token ("?before=" <> timeParam newerStart)
    assert "before excludes its boundary with full precision" (V.length beforeRows == 4)
    Page betweenRows _ <-
        list token ("?from=" <> timeParam olderStart <> "&before=" <> timeParam newerStart)
    assert "Two precise boundaries" (V.length betweenRows == 1)
    Page emptyGroup _ <- list token "?groupId=00000000-0000-0000-0000-000000000001"
    assert "No stored group memberships match" (V.null emptyGroup)
    void (rawCall env "GET" "/api/v1/workouts?limit=0" (bearer token) "" 400)
    void (rawCall env "GET" "/api/v1/workouts?sport=swimming" (bearer token) "" 400)
    void
        ( rawCall
            env
            "GET"
            ("/api/v1/workouts?from=" <> timeParam newerStart <> "&before=" <> timeParam olderStart)
            (bearer token)
            ""
            400
        )
    Page pageOne cursor <- list token "?limit=1"
    next <- maybe (fail "Missing workout cursor") pure cursor
    Page pageTwo _ <- list token ("?limit=1&cursor=" <> Text.encodeUtf8 next)
    assert "Pages do not repeat their boundary" (pageOne /= pageTwo && V.length pageTwo == 1)
    paged <- collect token "?limit=1"
    assert "Pagination covers every workout exactly once" (paged == V.toList allRows)
    void
        (rawCall env "GET" ("/api/v1/workouts?cursor=" <> Text.encodeUtf8 next) (bearer bobToken) "" 400)
    void
        ( rawCall
            env
            "GET"
            ("/api/v1/workouts?sport=running&cursor=" <> Text.encodeUtf8 next)
            (bearer token)
            ""
            400
        )
    void
        ( rawCall
            env
            "GET"
            ("/api/v1/workouts?cursor=" <> Text.encodeUtf8 (next <> "x"))
            (bearer token)
            ""
            400
        )
    listResponse <- rawCall env "GET" "/api/v1/workouts" (bearer token) "" 200
    assert
        "List omits full observations and sample streams"
        (not ("observationSport" `BS.isInfixOf` LBS.toStrict (simpleBody listResponse)))
    void
        ( rawCall
            env
            "DELETE"
            (workoutPath (workoutId first) <> "?expectedRevision=2&deleteEmptyGroups=true")
            (bearer bobToken)
            ""
            404
        )
    void
        ( rawCall
            env
            "DELETE"
            (workoutPath (workoutId first) <> "?expectedRevision=1&deleteEmptyGroups=true")
            (bearer token)
            ""
            409
        )
    void
        ( rawCall
            env
            "DELETE"
            (workoutPath (workoutId first) <> "?expectedRevision=2&deleteEmptyGroups=false")
            (bearer token)
            ""
            204
        )
    void (rawCall env "GET" (workoutPath (workoutId first)) (bearer token) "" 404)
    void (call env "POST" "/api/v1/workouts" (bearer token) request 404)
    void
        ( call
            env
            "POST"
            "/api/v1/workouts"
            (bearer token)
            (Api.ManualWorkout submission F.observation changed)
            409
        )
    Page afterDelete _ <- list token ""
    assert "Deletion cannot be undone by retrying creation" (V.length afterDelete == 4)
    user <- db env (Users.findUserByUsername "workout.alice") >>= maybe (fail "Missing account") pure
    unmappedId <- WorkoutId <$> UUID.nextRandom
    db env (Workouts.createWorkout (U.userId user) (F.workout {workoutId = unmappedId}))
    curve <-
        rawCall env "GET" (workoutPath unmappedId <> "/power-curve") (bearer token) "" 200 >>= decoded
    assert
        "Power curve uses canonical data and revision"
        (curve == PowerCurve.calculate (F.workout {workoutId = unmappedId}))
    unchanged <- db env (Workouts.loadWorkout (U.userId user) unmappedId)
    assert
        "Power curve reads never backfill or write observations"
        (unchanged == Just (F.workout {workoutId = unmappedId}))
    legacy <- getWorkout token unmappedId
    assert
        "Legacy detail backfills without changing source or revision"
        ( Statistics.isCurrent legacy
            && workoutRevision legacy == WorkoutRevision 1
            && sourceObservation legacy == F.observation
        )
    stored <- db env (Workouts.loadWorkout (U.userId user) unmappedId)
    assert "Backfill is persisted" (stored == Just legacy)
    cached <- getWorkout token unmappedId
    assert "Repeated detail preserves calculation timestamp" (cached == legacy)
    void
        (db env (Workouts.replaceUserData (U.userId user) unmappedId (WorkoutRevision 1) emptyUserData))
    invalidated <- db env (Workouts.loadWorkout (U.userId user) unmappedId)
    assert
        "Revision change clears old calculation"
        (maybe False (not . Statistics.isCurrent) invalidated)
    refreshed <- getWorkout token unmappedId
    assert
        "Stale cache is regenerated for the new revision"
        ( Statistics.isCurrent refreshed
            && workoutRevision refreshed == WorkoutRevision 2
            && sourceObservation refreshed == F.observation
        )
    void
        ( rawCall
            env
            "DELETE"
            (workoutPath unmappedId <> "?expectedRevision=2&deleteEmptyGroups=true")
            (bearer token)
            ""
            409
        )
    let longTag = Text.replicate 5000 "t"
        taggedData = emptyUserData {workoutTags = V.singleton longTag}
        tagQuery = "?limit=1&tag=" <> Text.encodeUtf8 longTag
    tagSubmissionA <- Id <$> UUID.nextRandom
    tagSubmissionB <- Id <$> UUID.nextRandom
    void (create token (Api.ManualWorkout tagSubmissionA F.observation taggedData))
    void (create token (Api.ManualWorkout tagSubmissionB F.observation taggedData))
    Page tagFirst tagCursor <- list token tagQuery
    tagNext <- maybe (fail "Missing long-filter cursor") pure tagCursor
    assert "Large filters still produce bounded cursors" (Text.length tagNext < 8192)
    Page tagSecond _ <- list token (tagQuery <> "&cursor=" <> Text.encodeUtf8 tagNext)
    assert "Large-filter cursor round-trips" (V.length tagSecond == 1 && tagFirst /= tagSecond)
    let curvePath = workoutPath (workoutId running) <> "/power-curve"
    void (rawCall env "GET" curvePath [] "" 401)
    void (rawCall env "GET" curvePath (bearer bobToken) "" 404)
    void (rawCall env "GET" (workoutPath (workoutId first) <> "/power-curve") (bearer token) "" 404)
    emptyCurve <-
        rawCall env "GET" (workoutPath (workoutId older) <> "/power-curve") (bearer token) "" 200
            >>= decoded @PC.PowerCurve
    assert
        "No power remains unavailable rather than zero"
        (V.all (isNothing . PC.best) (PC.points emptyCurve))
    let power = V.fromList [Timed (F.at t) (Power 200) | t <- [0 .. 60]]
        withPower sport = case sport of
            Cycling dat -> Cycling dat {cyclingMotion = (cyclingMotion dat) {motionPower = power}}
            Running dat -> Running dat {runningMotion = (runningMotion dat) {motionPower = power}}
    mapM_
        ( \source -> do
            sid <- Id <$> UUID.nextRandom
            let obs = workoutObservation source
                observation =
                    obs
                        { observationRange = TimeRange F.start (F.at 20000)
                        , observationSport = withPower (observationSport obs)
                        }
            w <- create token (Api.ManualWorkout sid observation emptyUserData)
            response <- rawCall env "GET" (workoutPath (workoutId w) <> "/power-curve") (bearer token) "" 200
            result <- decoded @PC.PowerCurve response
            assert
                "Private curve responses cannot be cached"
                (lookup "Cache-Control" (simpleHeaders response) == Just "no-store")
            assert
                "Both sports expose the correct full-minute effort"
                ( fmap PC.averagePower (PC.best =<< V.find ((== 60) . PC.durationSeconds) (PC.points result))
                    == Just (Power 200)
                )
        )
        [F.workout, F.runningWorkout]
    putStrLn
        "HTTP cycling/running persistence, owner isolation, concurrent retries, exact pagination, edits and tombstones passed"
  where
    create token request = call env "POST" "/api/v1/workouts" (bearer token) request 200 >>= decoded @Workout
    getWorkout token wid = rawCall env "GET" (workoutPath wid) (bearer token) "" 200 >>= decoded
    list token suffix =
        rawCall env "GET" ("/api/v1/workouts" <> suffix) (bearer token) "" 200
            >>= decoded @(Page Api.WorkoutCard)
    tinyRun token offset = do
        submission <- Id <$> UUID.nextRandom
        let range = TimeRange (addUTCTime offset (F.at 30000)) (F.at 30010)
            observation = WorkoutObservation range (Running emptyRunning) V.empty V.empty emptyAthlete V.empty V.empty
        create token (Api.ManualWorkout submission observation emptyUserData)
    collect token suffix = do
        Page rows cursor <- list token suffix
        rest <- maybe (pure []) (\next -> collect token ("?limit=1&cursor=" <> Text.encodeUtf8 next)) cursor
        pure (V.toList rows <> rest)
    position (Api.WorkoutCard (WorkoutId wid) _ range _ _) = (rangeStart range, wid)

workoutPath :: WorkoutId -> BS.ByteString
workoutPath (WorkoutId wid) = "/api/v1/workouts/" <> Text.encodeUtf8 (UUID.toText wid)

sourceObservation :: Workout -> WorkoutObservation
sourceObservation workout =
    let observation = workoutObservation workout
     in observation {observationSport = Sport.invalidateCalculated (observationSport observation)}
