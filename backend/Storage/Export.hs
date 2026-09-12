{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.Export (recordExport, listReceipts, isExportedObject) where

import Api.Common.Types (Id (..), Timestamp (..))
import qualified Api.Export.Types as Api
import Control.Monad (unless, void)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (throwE)
import Data.Coerce (coerce)
import Data.Int (Int32)
import Data.Profunctor (lmap)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import qualified Data.UUID.Types as UUID
import Data.Vector (Vector)
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import Storage.Types
import Storage.User.Types (UserId (..))
import qualified Storage.Workout as Workouts
import Text.Read (readMaybe)
import Workout.Types

recordExport
    :: UserId -> WorkoutId -> UUID -> UTCTime -> Api.RecordExport -> Store Api.ExportReceipt
recordExport uid wid receiptId now (Api.RecordExport revision Api.AppleHealth external) = do
    current <- Workouts.loadWorkout uid wid >>= maybe (throwE WorkoutNotFound) pure
    unless
        (revision > WorkoutRevision 0 && revision <= workoutRevision current)
        (throwE WorkoutConflict)
    object <- maybe (throwE InvalidExportReceipt) pure (UUID.fromText external)
    unless (object /= UUID.nil) (throwE InvalidExportReceipt)
    void $
        lift $
            T.statement (uid, wid, receiptId, Workouts.revisionText revision, object, now) $
                lmap
                    (\(u, w, i, r, o, at) -> (coerce u, coerce w, i, r, o, at))
                    [TH.rowsAffectedStatement|
                INSERT INTO export_receipts (user_id, workout_id, live_workout_id, id, workout_revision, platform, external_id, exported_at)
                VALUES ($1 :: uuid, $2 :: uuid, $2 :: uuid, $3 :: uuid, ($4 :: text) :: numeric, 'appleHealth', $5 :: uuid, $6 :: timestamptz)
                ON CONFLICT (user_id, platform, external_id) DO NOTHING
            |]
    row <-
        lift $
            T.statement (uid, object) $
                lmap
                    coerce
                    [TH.maybeStatement|
            SELECT id :: uuid, workout_id :: uuid, workout_revision :: text, external_id :: uuid, exported_at :: timestamptz
            FROM export_receipts WHERE user_id = $1 :: uuid AND platform = 'appleHealth' AND external_id = $2 :: uuid
        |]
    receipt@(Api.ExportReceipt _ original originalRevision _ _ _) <-
        maybe (throwE CorruptExportReceipt) decode row
    unless (original == wid && originalRevision == revision) (throwE ExportReceiptConflict)
    pure receipt

listReceipts
    :: UserId -> WorkoutId -> Maybe (UTCTime, UUID) -> Int32 -> Store (Vector Api.ExportReceipt)
listReceipts uid wid after limit = do
    void (Workouts.loadWorkout uid wid >>= maybe (throwE WorkoutNotFound) pure)
    rows <-
        lift $
            T.statement (uid, wid, fst <$> after, snd <$> after, limit) $
                lmap
                    (\(u, w, at, i, count) -> (coerce u, coerce w, at, i, count))
                    [TH.vectorStatement|
                SELECT id :: uuid, workout_id :: uuid, workout_revision :: text, external_id :: uuid, exported_at :: timestamptz
                FROM export_receipts
                WHERE user_id = $1 :: uuid AND workout_id = $2 :: uuid
                  AND ($3 :: timestamptz? IS NULL OR (exported_at, id) < ($3 :: timestamptz?, $4 :: uuid?))
                ORDER BY exported_at DESC, id DESC LIMIT $5 :: int4
            |]
    traverse decode rows

isExportedObject :: UserId -> UUID -> Store Bool
isExportedObject uid object =
    lift $
        T.statement (uid, object) $
            lmap
                coerce
                [TH.singletonStatement|
        SELECT EXISTS (SELECT 1 FROM export_receipts
            WHERE user_id = $1 :: uuid AND platform = 'appleHealth' AND external_id = $2 :: uuid) :: bool
    |]

decode :: (UUID, UUID, Text, UUID, UTCTime) -> Store Api.ExportReceipt
decode (iid, wid, revision, object, at) = case readMaybe (Text.unpack revision) of
    Just value
        | value > 0 ->
            pure
                ( Api.ExportReceipt
                    (Id iid)
                    (WorkoutId wid)
                    (WorkoutRevision value)
                    Api.AppleHealth
                    (UUID.toText object)
                    (Timestamp at)
                )
    _ -> throwE CorruptExportReceipt
