{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.Workout.Submission (createManual, deleteManual) where

import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (throwE)
import Data.Aeson (encode)
import Data.ByteArray (convert)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Coerce (coerce)
import Data.Profunctor (lmap)
import Data.UUID.Types (UUID)
import qualified Data.UUID.Types as UUID
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import Storage.Types
import Storage.User.Types (UserId (..))
import qualified Storage.Workout as Workouts
import Workout.Types
import "crypton" Crypto.Hash (Digest, SHA256, hash)

createManual :: UserId -> UUID -> Workout -> Store Workout
createManual uid submission workout = do
    unless (submission /= UUID.nil) (throwE SubmissionConflict)
    let digest =
            convert
                (hash (LBS.toStrict (encode (workoutObservation workout, workoutUserData workout))) :: Digest SHA256)
                :: BS.ByteString
    claimed <-
        lift $
            T.statement (uid, submission, digest) $
                lmap
                    coerce
                    [TH.rowsAffectedStatement|
                        INSERT INTO workout_submissions (user_id, submission_id, request_digest)
                        VALUES ($1 :: uuid, $2 :: uuid, $3 :: bytea) ON CONFLICT DO NOTHING
                    |]
    if claimed == 1
        then do
            Workouts.createWorkout uid workout
            lift $
                T.statement (uid, submission, workoutId workout) $
                    lmap
                        coerce
                        [TH.resultlessStatement|
                            UPDATE workout_submissions SET workout_id = $3 :: uuid
                            WHERE user_id = $1 :: uuid AND submission_id = $2 :: uuid
                        |]
            pure workout
        else do
            existing <-
                lift $
                    T.statement (uid, submission) $
                        lmap
                            coerce
                            [TH.maybeStatement|
                                SELECT request_digest :: bytea, workout_id :: uuid?
                                FROM workout_submissions
                                WHERE user_id = $1 :: uuid AND submission_id = $2 :: uuid FOR UPDATE
                            |]
            case existing of
                Just (original, wid) | original == digest -> do
                    identity <- maybe (throwE WorkoutNotFound) (pure . WorkoutId) wid
                    Workouts.loadWorkout uid identity >>= maybe (throwE WorkoutNotFound) pure
                _ -> throwE SubmissionConflict

-- Import/group persistence is not mounted yet. Reject workouts with no manual
-- submission mapping so later source imports cannot accidentally bypass policy.
deleteManual :: UserId -> WorkoutId -> WorkoutRevision -> Store ()
deleteManual uid wid expected = do
    current <- Workouts.loadWorkout uid wid >>= maybe (throwE WorkoutNotFound) pure
    unless (workoutRevision current == expected) (throwE WorkoutConflict)
    manual <-
        lift $
            T.statement (uid, wid) $
                lmap
                    coerce
                    [TH.singletonStatement|
                        SELECT EXISTS (SELECT 1 FROM workout_submissions
                            WHERE user_id = $1 :: uuid AND workout_id = $2 :: uuid) :: bool
                    |]
    unless manual (throwE WorkoutNotManual)
    count <-
        lift $
            T.statement (uid, wid, Workouts.revisionText expected) $
                lmap
                    coerce
                    [TH.rowsAffectedStatement|
                        DELETE FROM workouts WHERE user_id = $1 :: uuid AND id = $2 :: uuid
                            AND revision = ($3 :: text) :: numeric
                    |]
    unless (count == 1) (throwE WorkoutConflict)
