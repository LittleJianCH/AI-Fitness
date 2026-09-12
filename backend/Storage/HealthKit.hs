{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.HealthKit (submit, loadImport, deleteWorkout) where

import Api.Common.Types (Id (..), Revision (..), Timestamp (..))
import qualified Api.Import.Types as Api
import Control.Monad (unless, void)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (throwE)
import Data.Aeson (Result (..), Value, fromJSON, toJSON)
import Data.Coerce (coerce)
import Data.Int (Int16)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Profunctor (lmap)
import qualified Data.Text as Text
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import qualified Data.UUID.Types as UUID
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import Storage.Codec (jsonErrors, validText)
import qualified Storage.Export as Export
import Storage.Types
import Storage.User.Types (UserId (..))
import qualified Storage.Workout as Workouts
import qualified Storage.Workout.Statistics as Statistics
import qualified Storage.Workout.Submission as Manual
import qualified Workout.Sport as Sport
import Workout.Types
import qualified Workout.Validation as Validation

-- A synchronous transaction claims the owner/object identity and publishes both
-- canonical data and its acknowledgement. There is no externally visible claim
-- to recover after a crash: a failed transaction rolls the whole attempt back.
submit
    :: UserId -> UUID -> WorkoutId -> UTCTime -> Api.HealthKitSubmission -> Store Api.ImportRecord
submit uid freshImport freshWorkout now submission@(Api.HealthKitSubmission object intent expectedImport expectedWorkouts parts) = do
    unless (validSubmission submission) (throwE InvalidImport)
    let initial =
            Api.ImportRecord
                (Id freshImport)
                (Revision 1)
                (Api.HealthKit (Api.HealthKitSource object))
                Api.Pending
                Api.NotApplicable
                (Timestamp now)
                (Timestamp now)
                Nothing
                Nothing
    void $
        lift $
            T.statement (uid, freshImport, object, toJSON initial) $
                lmap
                    (\(u, i, o, record) -> (coerce u, i, coerce o, record))
                    [TH.rowsAffectedStatement|
                INSERT INTO healthkit_imports (user_id, id, object_id, storage_version, record)
                VALUES ($1 :: uuid, $2 :: uuid, $3 :: uuid, 1, $4 :: jsonb)
                ON CONFLICT (user_id, object_id) DO NOTHING
            |]
    stored <-
        lift $
            T.statement (uid, object) $
                lmap
                    coerce
                    [TH.maybeStatement|
            SELECT id :: uuid, object_id :: uuid, storage_version :: int2, record :: jsonb, workout_id :: uuid?
            FROM healthkit_imports WHERE user_id = $1 :: uuid AND object_id = $2 :: uuid FOR UPDATE
        |]
    (record, liveWorkout) <- maybe (throwE CorruptImport) decode stored
    let Api.ImportRecord _ revision _ status _ _ _ previous _ = record
    exported <- Export.isExportedObject uid (coerce object)
    if exported && status /= Api.Suppressed
        then do
            let suppressed = advance now Api.Suppressed previous Nothing record
            save uid suppressed liveWorkout
            pure suppressed
        else
            if status == Api.Suppressed
                then pure record
                else case intent of
                    Api.Normal | isJust previous -> pure record
                    Api.Normal | status == Api.Failed -> pure record
                    Api.Normal -> publish record liveWorkout
                    Api.Retry -> do
                        unless (expectedImport == Just revision) (throwE ImportConflict)
                        unless (isNothing previous) (throwE ImportRefreshRequired)
                        unless (status == Api.Failed) (throwE ImportRetryRequired)
                        publish record liveWorkout
                    Api.Refresh -> do
                        unless (expectedImport == Just revision) (throwE ImportConflict)
                        unless (isJust previous) (throwE ImportReconciliationRequired)
                        publish record liveWorkout
  where
    Api.ImportPart partKey observation initialUserData = NE.head parts
    publish record liveWorkout = do
        let Api.ImportRecord _ _ _ _ _ _ _ previous _ = record
        (wid, userData, revision) <- case previous of
            Nothing -> pure (freshWorkout, initialUserData, Nothing)
            Just (Api.ImportOutput (Api.ImportedPart key wid :| []) Nothing _ _) -> do
                unless (key == partKey && liveWorkout == Just (coerce wid)) (throwE ImportReconciliationRequired)
                expected <- case expectedWorkouts of
                    [Api.ExpectedWorkout expectedId revision] | expectedId == wid -> pure revision
                    _ -> throwE ImportReconciliationRequired
                current <- Workouts.loadWorkout uid wid >>= maybe (throwE ImportReconciliationRequired) pure
                unless (workoutRevision current == expected) (throwE WorkoutConflict)
                pure (wid, workoutUserData current, Just expected)
            _ -> throwE ImportReconciliationRequired
        let candidate = Workout wid (fromMaybe (WorkoutRevision 1) revision) observation userData
            errors =
                Validation.validateWorkout candidate
                    <> jsonErrors "observation" (toJSON observation)
                    <> jsonErrors "userData" (toJSON userData)
        if not (null errors)
            then do
                let failed =
                        advance
                            now
                            Api.Failed
                            previous
                            (Just (Api.Failure "validation_failed" "HealthKit data did not pass canonical validation" True))
                            record
                save uid failed liveWorkout
                pure failed
            else do
                case revision of
                    Nothing -> Workouts.createWorkout uid candidate
                    Just expected -> void (Workouts.replaceObservation uid wid expected observation)
                void (Statistics.refresh now uid wid)
                let output =
                        Api.ImportOutput
                            (Api.ImportedPart partKey wid :| [])
                            Nothing
                            "healthkit-normalized-v1"
                            (Timestamp now)
                    succeeded = advance now Api.Succeeded (Just output) Nothing record
                save uid succeeded (Just (coerce wid))
                pure succeeded

-- Batch selection submits separate source objects. A multisport object must not
-- be flattened or partially published; grouped HealthKit support is separate.
validSubmission :: Api.HealthKitSubmission -> Bool
validSubmission (Api.HealthKitSubmission (Id object) intent expected expectedWorkouts parts) =
    object /= UUID.nil && length parts == 1 && all validPart parts && case intent of
        Api.Normal -> isNothing expected && null expectedWorkouts
        Api.Retry -> positive expected && null expectedWorkouts
        Api.Refresh ->
            positive expected && case expectedWorkouts of
                [Api.ExpectedWorkout (WorkoutId wid) (WorkoutRevision revision)] -> wid /= UUID.nil && revision > 0
                _ -> False
  where
    positive (Just (Revision n)) = n > 0
    positive Nothing = False
    validPart (Api.ImportPart key observation _) =
        validText key
            && not (Text.null (Text.strip key))
            && Text.length key <= 256
            && Sport.invalidateCalculated (observationSport observation) == observationSport observation

loadImport :: UserId -> Id "Import" -> Store Api.ImportRecord
loadImport uid iid = do
    row <-
        lift $
            T.statement (uid, iid) $
                lmap
                    coerce
                    [TH.maybeStatement|
            SELECT id :: uuid, object_id :: uuid, storage_version :: int2, record :: jsonb, workout_id :: uuid?
            FROM healthkit_imports WHERE user_id = $1 :: uuid AND id = $2 :: uuid
        |]
    maybe (throwE ImportNotFound) (fmap fst . decode) row

deleteWorkout :: UserId -> WorkoutId -> WorkoutRevision -> UTCTime -> Store ()
deleteWorkout uid wid expected now = do
    row <-
        lift $
            T.statement (uid, wid) $
                lmap
                    coerce
                    [TH.maybeStatement|
            SELECT id :: uuid, object_id :: uuid, storage_version :: int2, record :: jsonb, workout_id :: uuid?
            FROM healthkit_imports WHERE user_id = $1 :: uuid AND workout_id = $2 :: uuid FOR UPDATE
        |]
    case row of
        Nothing -> Manual.deleteManual uid wid expected
        Just stored -> do
            (record, _) <- decode stored
            current <- Workouts.loadWorkout uid wid >>= maybe (throwE WorkoutNotFound) pure
            unless (workoutRevision current == expected) (throwE WorkoutConflict)
            let Api.ImportRecord _ _ _ _ _ _ _ previous _ = record
            save uid (advance now Api.Suppressed previous Nothing record) Nothing
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

advance
    :: UTCTime
    -> Api.ImportStatus
    -> Maybe Api.ImportOutput
    -> Maybe Api.Failure
    -> Api.ImportRecord
    -> Api.ImportRecord
advance now status output failure (Api.ImportRecord iid (Revision revision) source _ archive created _ _ _) =
    Api.ImportRecord
        iid
        (Revision (revision + 1))
        source
        status
        archive
        created
        (Timestamp now)
        output
        failure

save :: UserId -> Api.ImportRecord -> Maybe UUID -> Store ()
save uid record@(Api.ImportRecord iid _ _ _ _ _ _ _ _) wid = do
    count <-
        lift $
            T.statement (uid, iid, toJSON record, wid) $
                lmap
                    (\(u, i, value, w) -> (coerce u, coerce i, value, w))
                    [TH.rowsAffectedStatement|
                UPDATE healthkit_imports SET record = $3 :: jsonb, workout_id = $4 :: uuid?
                WHERE user_id = $1 :: uuid AND id = $2 :: uuid
            |]
    unless (count == 1) (throwE CorruptImport)

decode :: (UUID, UUID, Int16, Value, Maybe UUID) -> Store (Api.ImportRecord, Maybe UUID)
decode (iid, object, version, value, wid) = case fromJSON value of
    Success
        record@( Api.ImportRecord
                    (Id storedId)
                    (Revision revision)
                    (Api.HealthKit (Api.HealthKitSource (Id storedObject)))
                    _
                    Api.NotApplicable
                    _
                    _
                    _
                    _
                )
            | version == 1 && iid == storedId && object == storedObject && revision > 0 -> pure (record, wid)
    _ -> throwE CorruptImport
