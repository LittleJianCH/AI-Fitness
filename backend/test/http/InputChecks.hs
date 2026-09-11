{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module InputChecks (checks) where

import Api.Auth.Types (Credentials (..), NativeSession (..))
import Api.Common.Types (FieldError (..), Id (..), Problem (..))
import Api.Workout.Types (EditWorkout (..), ManualWorkout (..))
import App.Types
import Control.Monad (void)
import qualified Data.Text.Encoding as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import qualified Data.Vector as V
import qualified Fixtures as F
import qualified Hasql.Pool as Pool
import HttpSupport
import qualified Storage.Database as Database
import Storage.Types (StorageError (..))
import qualified Storage.User as Users
import qualified Storage.User.Types as U
import qualified Storage.Workout as Workouts
import Workout.Empty
import Workout.Types

checks :: Environment -> IO ()
checks env = do
    registerUser env "input.alice"
    NativeSession _ _ token <- loginNative env "input.alice" testPassword
    submission <- Id <$> UUID.nextRandom
    let nulData = emptyUserData {workoutNotes = Just "before\0after"}
        safeData = emptyUserData {workoutNotes = Just "literal \\u0000 remains text"}
    Problem _ _ _ errors <-
        call
            env
            "POST"
            "/api/v1/workouts"
            (bearer token)
            (ManualWorkout submission F.observation nulData)
            422
            >>= decoded
    assert
        "Unrepresentable text has a field error"
        (any (\(FieldError path _ _) -> path == "userData.workoutNotes") errors)
    created <-
        call
            env
            "POST"
            "/api/v1/workouts"
            (bearer token)
            (ManualWorkout submission F.observation safeData)
            200
            >>= decoded @Workout
    let WorkoutId wid = workoutId created
        path = "/api/v1/workouts/" <> Text.encodeUtf8 (UUID.toText wid)
    void
        (call env "PUT" (path <> "/user-data") (bearer token) (EditWorkout (WorkoutRevision 1) nulData) 422)
    after <- rawCall env "GET" path (bearer token) "" 200 >>= decoded
    assert "Rejected metadata update changes neither content nor revision" (after == created)
    let nulObservation = F.observation {observationDataIssues = V.singleton (DataIssue "test" Nothing "invalid\0text")}
    otherSubmission <- Id <$> UUID.nextRandom
    void
        ( call
            env
            "POST"
            "/api/v1/workouts"
            (bearer token)
            (ManualWorkout otherSubmission nulObservation safeData)
            422
        )
    user <- db env (Users.findUserByUsername "input.alice") >>= maybe (fail "Missing test user") pure
    updated <-
        Pool.use
            (databasePool env)
            ( Database.transaction
                (Workouts.replaceObservation (U.userId user) (workoutId created) (WorkoutRevision 1) nulObservation)
            )
    assert
        "Observation replacement checks storage text"
        (case updated of Right (Left (InvalidWorkout _)) -> True; _ -> False)
    again <- rawCall env "GET" path (bearer token) "" 200 >>= decoded
    assert "Rejected observation update is atomic" (again == created)
    void
        ( call
            env
            "POST"
            "/api/v1/auth/native/login"
            []
            (Credentials "input.alice" testPassword (Just "phone\0name"))
            422
        )
    void (rawCall env "GET" "/api/v1/workouts?tag=bad%00tag" (bearer token) "" 400)
    putStrLn "Unsupported PostgreSQL text is rejected without lost content or database errors"
