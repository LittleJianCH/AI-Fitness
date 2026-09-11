{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

module Storage.Workout.Submission (createManual, deleteManual) where

import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (throwE)
import Data.Aeson (encode)
import Data.ByteArray (convert)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Functor.Contravariant ((>$<))
import Data.UUID.Types (UUID)
import qualified Data.UUID.Types as UUID
import qualified Hasql.Decoders as D
import qualified Hasql.Encoders as E
import Hasql.Statement (preparable)
import qualified Hasql.Transaction as T
import Storage.Codec
import Storage.Types
import Storage.User.Types (UserId)
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
                preparable
                    "INSERT INTO workout_submissions (user_id, submission_id, request_digest) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING"
                    ( ((\(u, _, _) -> u) >$< param userIdValue)
                        <> ((\(_, s, _) -> s) >$< param E.uuid)
                        <> ((\(_, _, d) -> d) >$< param E.bytea)
                    )
                    D.rowsAffected
    if claimed == 1
        then do
            Workouts.createWorkout uid workout
            let WorkoutId wid = workoutId workout
            lift $
                T.statement (uid, submission, wid) $
                    preparable
                        "UPDATE workout_submissions SET workout_id = $3 WHERE user_id = $1 AND submission_id = $2"
                        ( ((\(u, _, _) -> u) >$< param userIdValue)
                            <> ((\(_, s, _) -> s) >$< param E.uuid)
                            <> ((\(_, _, w) -> w) >$< param E.uuid)
                        )
                        D.noResult
            pure workout
        else do
            existing <-
                lift $
                    T.statement (uid, submission) $
                        preparable
                            "SELECT request_digest, workout_id FROM workout_submissions WHERE user_id = $1 AND submission_id = $2 FOR UPDATE"
                            ((fst >$< param userIdValue) <> (snd >$< param E.uuid))
                            (D.rowMaybe ((,) <$> column D.bytea <*> D.column (D.nullable D.uuid)))
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
    let WorkoutId value = wid
    manual <-
        lift $
            T.statement (uid, value) $
                preparable
                    "SELECT EXISTS (SELECT 1 FROM workout_submissions WHERE user_id = $1 AND workout_id = $2)"
                    ((fst >$< param userIdValue) <> (snd >$< param E.uuid))
                    (D.singleRow (column D.bool))
    unless manual (throwE WorkoutNotManual)
    count <-
        lift $
            T.statement (uid, value, Workouts.revisionText expected) $
                preparable
                    "DELETE FROM workouts WHERE user_id = $1 AND id = $2 AND revision = $3::text::numeric"
                    ( ((\(u, _, _) -> u) >$< param userIdValue)
                        <> ((\(_, w, _) -> w) >$< param E.uuid)
                        <> ((\(_, _, r) -> r) >$< param E.text)
                    )
                    D.rowsAffected
    unless (count == 1) (throwE WorkoutConflict)
