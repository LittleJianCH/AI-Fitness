{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent.Async (concurrently)
import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import qualified Data.ByteString as BS
import Data.Either (isLeft, isRight)
import Data.Maybe (isNothing)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (addUTCTime)
import qualified Data.UUID.Types as UUID
import qualified Fixtures as F
import qualified Hasql.Connection as Connection
import qualified Hasql.Transaction as T
import qualified Storage.Database as DB
import qualified Storage.Session as Sessions
import Storage.Session.Types
import Storage.Types
import qualified Storage.User as Users
import Storage.User.Types
import qualified Storage.Workout as Workouts
import System.Environment (getArgs, getEnv)
import qualified Workout.Sport as Sport
import Workout.Types

main :: IO ()
main = do
    url <- Text.pack <$> getEnv "AI_FITNESS_TEST_DATABASE_URL"
    args <- getArgs
    DB.withConnection url $ \connection -> case args of
        [] -> do
            userTests connection
            sessionTests connection
            workoutTests connection
            rollbackTests connection
            concurrencyTest url connection
            constraintTests connection
            putStrLn
                "Passed user/session/workout storage, ownership, rollback, constraints and concurrent revision checks"
        ["verify-restart"] -> do
            stored <- must connection (Workouts.loadWorkout alice F.otherId)
            assert "Running data survives a PostgreSQL restart" (stored == Just F.runningWorkout)
            user <- must connection (Users.loadUser alice)
            assert "User survives a PostgreSQL restart" (user == Just aliceUser)
            session <- must connection (Sessions.findActiveSession (sessionTokenDigest nativeSession) (F.at 10))
            assert "Session survives a PostgreSQL restart" (session == Just nativeSession)
            putStrLn "Passed PostgreSQL restart durability checks"
        _ -> fail "Unknown storage test arguments"

userTests :: Connection.Connection -> IO ()
userTests connection = do
    must connection $ Users.createUser aliceUser >> Users.createUser bobUser
    user <- must connection (Users.findUserByUsername "alice")
    assert "User and encoded credential round trip" (user == Just aliceUser)
    missing <- must connection (Users.findUserByUsername "alice' OR true --")
    assert "Username lookup is parameterized" (isNothing missing)
    conflict <- DB.runTransaction connection (Users.createUser (bobUser {username = "alice"}))
    assert "Username uniqueness is enforced" (conflict == Left UserConflict)
    rejected <-
        DB.runTransaction
            connection
            (Users.createUser (aliceUser {userId = uid 103, passwordHash = PasswordHash "plaintext"}))
    assert "Plaintext credentials are rejected" (rejected == Left DatabaseFailure)

sessionTests :: Connection.Connection -> IO ()
sessionTests connection = do
    let bootstrap = browserSession {sessionUserId = Nothing}
    must connection $ Sessions.createSession nativeSession >> Sessions.createSession bootstrap
    active <- must connection (Sessions.findActiveSession (sessionTokenDigest nativeSession) (F.at 10))
    assert "Active native session round trip" (active == Just nativeSession)
    anonymous <- must connection (Sessions.findActiveSession (sessionTokenDigest bootstrap) (F.at 10))
    assert "Browser bootstrap remains explicitly anonymous" (anonymous == Just bootstrap)
    expired <- must connection (Sessions.findActiveSession (sessionTokenDigest nativeSession) (F.at 60))
    assert "Idle deadline is exclusive" (isNothing expired)
    future <-
        must connection (Sessions.findActiveSession (sessionTokenDigest nativeSession) (F.at (-1)))
    assert "Future session is inactive" (isNothing future)
    must connection $
        Sessions.createSession (browserSession {sessionId = sid 203, sessionTokenDigest = digest 3})
    revokedByOther <- must connection (Sessions.revokeSession bob (sid 203) (F.at 10))
    assert "Another user cannot revoke a session" (not revokedByOther)
    revoked <- must connection (Sessions.revokeSession alice (sid 203) (F.at 10))
    assert "Owner can revoke a session" revoked
    inactive <- must connection (Sessions.findActiveSession (digest 3) (F.at 11))
    assert "Revoked session is inactive" (isNothing inactive)
    duplicate <-
        DB.runTransaction connection (Sessions.createSession (nativeSession {sessionId = sid 204}))
    assert "Duplicate token digest conflicts" (duplicate == Left SessionConflict)
    invalid <-
        DB.runTransaction
            connection
            ( Sessions.createSession
                (nativeSession {sessionId = sid 204, sessionTokenDigest = digest 4, sessionUserId = Nothing})
            )
    assert "Native session requires a user" (invalid == Left DatabaseFailure)
    noCsrf <-
        DB.runTransaction
            connection
            ( Sessions.createSession
                (browserSession {sessionId = sid 204, sessionTokenDigest = digest 4, sessionCsrfDigest = Nothing})
            )
    assert "Browser session requires CSRF digest" (noCsrf == Left DatabaseFailure)
    short <-
        DB.runTransaction
            connection
            ( Sessions.createSession
                (nativeSession {sessionId = sid 204, sessionTokenDigest = TokenDigest "short"})
            )
    assert "Token digests have the required length" (short == Left DatabaseFailure)
    invalidExpiry <-
        DB.runTransaction
            connection
            ( Sessions.createSession
                (nativeSession {sessionId = sid 204, sessionTokenDigest = digest 4, sessionIdleExpiresAt = F.at 121})
            )
    assert "Idle expiry cannot exceed absolute expiry" (invalidExpiry == Left DatabaseFailure)
    must connection $ do
        Sessions.createSession
            (nativeSession {sessionId = sid 205, sessionTokenDigest = digest 5, sessionUserId = Just bob})
        raw "UPDATE users SET disabled_at = '2026-09-05T05:55:42Z' WHERE username = 'bob'"
    disabled <- must connection (Sessions.findActiveSession (digest 5) (F.at 11))
    assert "Disabled account cannot resolve an active session" (isNothing disabled)
    must connection (raw "UPDATE users SET disabled_at = NULL WHERE username = 'bob'")
    count <- must connection (Sessions.revokeUserSessions bob (F.at 12))
    assert "Revoke-all is scoped to the owner" (count == 1)
    preserved <-
        must connection (Sessions.findActiveSession (sessionTokenDigest nativeSession) (F.at 13))
    assert "Revoke-all preserves another user's sessions" (preserved == Just nativeSession)

workoutTests :: Connection.Connection -> IO ()
workoutTests connection = do
    must connection $ Workouts.createWorkout alice ride >> Workouts.createWorkout alice F.runningWorkout
    stored <- must connection (Workouts.loadWorkout alice F.wid)
    assert "All cycling streams, extensions and large revision round trip" (stored == Just ride)
    storedRun <- must connection (Workouts.loadWorkout alice F.otherId)
    assert "All running streams round trip" (storedRun == Just F.runningWorkout)
    hidden <- must connection (Workouts.loadWorkout bob F.wid)
    assert "Other users see no workout" (isNothing hidden)
    absent <- must connection (Workouts.loadWorkout alice (WorkoutId (uuid 999)))
    assert "Unknown workout is absent" (isNothing absent)
    otherEdit <-
        DB.runTransaction connection (Workouts.replaceUserData bob F.wid largeRevision changedUserData)
    assert "Other users cannot edit a workout" (otherEdit == Left WorkoutNotFound)
    edited <- must connection (Workouts.replaceUserData alice F.wid largeRevision changedUserData)
    assert "User-data edit keeps observations" (workoutObservation edited == workoutObservation ride)
    assert "Revision increments beyond int64 without loss" (workoutRevision edited == nextRevision)
    stale <-
        DB.runTransaction
            connection
            (Workouts.replaceUserData alice F.wid largeRevision (workoutUserData ride))
    assert "Stale revision conflicts" (stale == Left WorkoutConflict)
    let observation =
            (workoutObservation ride)
                { observationAthlete = (observationAthlete (workoutObservation ride)) {athleteMass = Just (Mass 71)}
                }
    refreshed <- must connection (Workouts.replaceObservation alice F.wid nextRevision observation)
    assert
        "Observation replacement preserves user content"
        (workoutUserData refreshed == changedUserData)
    assert "Observation replacement persists" (workoutObservation refreshed == observation)
    let bad =
            F.runningWorkout
                { workoutId = WorkoutId (uuid 7)
                , workoutObservation =
                    (workoutObservation F.runningWorkout) {observationRange = TimeRange (F.at 30) F.start}
                }
    invalid <- DB.runTransaction connection (Workouts.createWorkout alice bad)
    assert
        "Canonical validation rejects invalid data"
        (case invalid of Left (InvalidWorkout _) -> True; _ -> False)
    notInserted <- must connection (Workouts.loadWorkout alice (WorkoutId (uuid 7)))
    assert "Invalid canonical data is not published" (isNothing notInserted)

rollbackTests :: Connection.Connection -> IO ()
rollbackTests connection = do
    let first = ride {workoutId = WorkoutId (uuid 10)}
    rolledBack <- DB.runTransaction connection $ do
        Workouts.createWorkout alice first
        Workouts.replaceUserData alice F.wid largeRevision changedUserData
    assert "Domain conflict aborts composed writes" (rolledBack == Left WorkoutConflict)
    missing <- must connection (Workouts.loadWorkout alice (workoutId first))
    assert "Earlier write rolls back on domain failure" (isNothing missing)
    sqlFailure <- DB.runTransaction connection $ do
        Workouts.createWorkout alice first
        raw "SELECT 1 / 0"
    assert "SQL failures are redacted" (sqlFailure == Left DatabaseFailure)
    stillMissing <- must connection (Workouts.loadWorkout alice (workoutId first))
    assert "Earlier write rolls back on SQL failure" (isNothing stillMissing)

concurrencyTest :: Text -> Connection.Connection -> IO ()
concurrencyTest url connection = do
    before <-
        must connection (Workouts.loadWorkout alice F.wid)
            >>= maybe (fail "Missing concurrency fixture") pure
    let write title = DB.withConnection url $ \other ->
            DB.runTransaction
                other
                ( Workouts.replaceUserData
                    alice
                    F.wid
                    (workoutRevision before)
                    (changedUserData {workoutTitle = Just title})
                )
    (left, right) <- concurrently (write "First edit") (write "Second edit")
    assert
        "Concurrent writers produce one winner and one conflict"
        ((isRight left && right == Left WorkoutConflict) || (left == Left WorkoutConflict && isRight right))
    after <-
        must connection (Workouts.loadWorkout alice F.wid) >>= maybe (fail "Missing race result") pure
    let WorkoutRevision revision = workoutRevision before
    assert "Concurrent update increments once" (workoutRevision after == WorkoutRevision (revision + 1))
    assert
        "Concurrent update preserves sensor streams"
        ( Sport.motion (observationSport (workoutObservation after))
            == Sport.motion (observationSport (workoutObservation before))
        )

constraintTests :: Connection.Connection -> IO ()
constraintTests connection = do
    invalidRevision <- DB.runTransaction connection (raw "UPDATE workouts SET revision = 1.5")
    assert "Database rejects fractional revisions" (invalidRevision == Left DatabaseFailure)
    invalidVersion <- DB.runTransaction connection (raw "UPDATE workouts SET storage_version = 2")
    assert "Database rejects unknown storage versions" (invalidVersion == Left DatabaseFailure)
    invalidShape <- DB.runTransaction connection (raw "UPDATE workouts SET observation = '{}'::jsonb")
    assert "Database rejects missing canonical structure" (invalidShape == Left DatabaseFailure)
    foreignOwner <-
        DB.runTransaction
            connection
            (Workouts.createWorkout (uid 999) (ride {workoutId = WorkoutId (uuid 999)}))
    assert "Foreign key requires a real owner" (foreignOwner == Left DatabaseFailure)
    -- Simulate structurally plausible corruption by a maintenance client. The
    -- Haskell read boundary must not return an invalid canonical value.
    must
        connection
        ( raw
            "UPDATE workouts SET observation = observation - 'observationEvents' WHERE id = '00000000-0000-0000-0000-000000000001'"
        )
    corrupt <- DB.runTransaction connection (Workouts.loadWorkout alice F.wid)
    assert "Corrupt canonical payload fails closed" (corrupt == Left CorruptWorkout)
    assert "Failure is not mistaken for a missing workout" (isLeft corrupt)

raw :: BS.ByteString -> Store ()
raw = lift . T.sql

must :: Connection.Connection -> Store a -> IO a
must connection action = DB.runTransaction connection action >>= either (fail . show) pure

assert :: String -> Bool -> IO ()
assert name ok = unless ok (fail name)

uuid :: Word -> UUID.UUID
uuid value = UUID.fromWords 0 0 0 (fromIntegral value)

uid :: Word -> UserId
uid = UserId . uuid

sid :: Word -> SessionId
sid = SessionId . uuid

digest :: Word -> TokenDigest
digest = TokenDigest . BS.replicate 32 . fromIntegral

alice, bob :: UserId
alice = uid 101
bob = uid 102

aliceUser, bobUser :: StoredUser
aliceUser =
    StoredUser
        alice
        "alice"
        (PasswordHash "$argon2id$v=19$m=65536,t=3,p=1$syntheticSalt$syntheticHash")
        F.start
        Nothing
bobUser = aliceUser {userId = bob, username = "bob"}

nativeSession, browserSession :: StoredSession
nativeSession =
    StoredSession
        (sid 201)
        (Just alice)
        (digest 1)
        Native
        Nothing
        (Just "Test device")
        F.start
        F.start
        (F.at 60)
        (F.at 120)
        Nothing
browserSession =
    nativeSession
        { sessionId = sid 202
        , sessionTokenDigest = digest 2
        , sessionTransport = Browser
        , sessionCsrfDigest = Just (digest 20)
        }

largeRevision, nextRevision :: WorkoutRevision
largeRevision = WorkoutRevision 9223372036854775808
nextRevision = WorkoutRevision 9223372036854775809

ride :: Workout
ride =
    F.workout
        { workoutRevision = largeRevision
        , workoutObservation =
            (workoutObservation F.workout)
                { observationRange = F.rideRange {rangeEnd = addUTCTime 0.125123456789 (rangeEnd F.rideRange)}
                }
        }

changedUserData :: WorkoutUserData
changedUserData =
    (workoutUserData ride) {workoutTitle = Just "My revised ride", workoutNotes = Just "Keep my notes"}
