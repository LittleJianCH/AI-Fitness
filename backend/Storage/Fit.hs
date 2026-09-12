{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.Fit (findImport, loadImport, publish, deleteWorkout) where

import Api.Common.Types (Id (..), Revision (..), Timestamp (..))
import qualified Api.Import.Types as Api
import Control.Monad (unless, void)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (throwE)
import Data.Aeson (Result (..), Value, fromJSON, toJSON)
import Data.Coerce (coerce)
import Data.Int (Int16)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Profunctor (lmap)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import qualified Storage.HealthKit as HealthKit
import Storage.Types
import Storage.User.Types (UserId (..))
import qualified Storage.Workout as Workouts
import qualified Storage.Workout.Statistics as Statistics
import Workout.Empty (emptyUserData)
import Workout.Types

-- The caller holds the account lock via Auth.Session.owned. SDK and archive IO
-- finish before this transaction. A concurrent uploader observes the winner;
-- file identity never compares times or observations from independent sources.
publish
    :: UserId
    -> UUID
    -> WorkoutId
    -> Text
    -> UTCTime
    -> Either Api.Failure WorkoutObservation
    -> Store Api.ImportRecord
publish uid iid wid sha now result = do
    existing <- findImport uid sha
    maybe publishNew pure existing
  where
    publishNew = do
        output <- either (const (pure Nothing)) publishWorkout result
        let record =
                Api.ImportRecord
                    (Id iid)
                    (Revision 1)
                    (Api.Fit (Api.FitSource sha))
                    (either (const Api.Failed) (const Api.Succeeded) result)
                    Api.Retained
                    (Timestamp now)
                    (Timestamp now)
                    output
                    (either Just (const Nothing) result)
            liveWorkout = either (const Nothing) (const (Just (coerce wid))) result
        void $
            lift $
                T.statement
                    (coerce uid, iid, sha, toJSON record, liveWorkout)
                    [TH.rowsAffectedStatement|
                INSERT INTO fit_imports (user_id, id, sha256, storage_version, record, workout_id)
                VALUES ($1 :: uuid, $2 :: uuid, $3 :: text, 1, $4 :: jsonb, $5 :: uuid?)
            |]
        pure record
    publishWorkout observation = do
        Workouts.createWorkout uid (Workout wid (WorkoutRevision 1) observation emptyUserData)
        void (Statistics.refresh now uid wid)
        pure $
            Just
                ( Api.ImportOutput
                    (Api.ImportedPart "session" wid :| [])
                    Nothing
                    "garmin-fit-v1"
                    (Timestamp now)
                )

findImport :: UserId -> Text -> Store (Maybe Api.ImportRecord)
findImport uid sha = do
    row <-
        lift $
            T.statement
                (coerce uid, sha)
                [TH.maybeStatement|
            SELECT id :: uuid, sha256 :: text, storage_version :: int2, record :: jsonb
            FROM fit_imports WHERE user_id = $1 :: uuid AND sha256 = $2 :: text
        |]
    traverse decode row

loadImport :: UserId -> Id "Import" -> Store (Maybe Api.ImportRecord)
loadImport uid iid = do
    row <-
        lift $
            T.statement (uid, iid) $
                lmap
                    coerce
                    [TH.maybeStatement|
            SELECT id :: uuid, sha256 :: text, storage_version :: int2, record :: jsonb
            FROM fit_imports WHERE user_id = $1 :: uuid AND id = $2 :: uuid
        |]
    traverse decode row

-- Keep the source tombstone so reupload cannot resurrect a deleted workout.
deleteWorkout :: UserId -> WorkoutId -> WorkoutRevision -> UTCTime -> Store ()
deleteWorkout uid wid expected now = do
    row <-
        lift $
            T.statement (uid, wid) $
                lmap
                    coerce
                    [TH.maybeStatement|
            SELECT id :: uuid, sha256 :: text, storage_version :: int2, record :: jsonb
            FROM fit_imports WHERE user_id = $1 :: uuid AND workout_id = $2 :: uuid FOR UPDATE
        |]
    maybe (HealthKit.deleteWorkout uid wid expected now) suppress row
  where
    suppress stored = do
        Api.ImportRecord iid (Revision revision) source _ archive created _ previous _ <-
            decode stored
        current <- Workouts.loadWorkout uid wid >>= maybe (throwE WorkoutNotFound) pure
        unless (workoutRevision current == expected) (throwE WorkoutConflict)
        let record =
                Api.ImportRecord
                    iid
                    (Revision (revision + 1))
                    source
                    Api.Suppressed
                    archive
                    created
                    (Timestamp now)
                    previous
                    Nothing
        void $
            lift $
                T.statement
                    (coerce uid, coerce iid, toJSON record)
                    [TH.rowsAffectedStatement|
                UPDATE fit_imports SET record = $3 :: jsonb, workout_id = NULL
                WHERE user_id = $1 :: uuid AND id = $2 :: uuid
            |]
        count <-
            lift $
                T.statement
                    (coerce uid, coerce wid, Workouts.revisionText expected)
                    [TH.rowsAffectedStatement|
                DELETE FROM workouts WHERE user_id = $1 :: uuid AND id = $2 :: uuid
                AND revision = ($3 :: text) :: numeric
            |]
        unless (count == 1) (throwE WorkoutConflict)

decode :: (UUID, Text, Int16, Value) -> Store Api.ImportRecord
decode (iid, sha, version, value) = case fromJSON value of
    Success
        record@( Api.ImportRecord
                    (Id storedId)
                    (Revision revision)
                    (Api.Fit (Api.FitSource storedSha))
                    _
                    Api.Retained
                    _
                    _
                    _
                    _
                )
            | version == 1 && iid == storedId && sha == storedSha && revision > 0 -> pure record
    _ -> throwE CorruptImport
