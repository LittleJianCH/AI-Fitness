{-# LANGUAGE OverloadedStrings #-}

module Storage.Workout (createWorkout, loadWorkout, replaceUserData, replaceObservation) where

import Api.Workout.Codec ()
import Control.Monad.Trans.Except (ExceptT (..))
import Data.Aeson (Result (..), Value, fromJSON, toJSON)
import Data.Functor.Contravariant (contramap, (>$<))
import Data.Int (Int16)
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Hasql.Decoders as D
import qualified Hasql.Encoders as E
import Hasql.Statement (preparable)
import qualified Hasql.Transaction as T
import Storage.Codec
import Storage.Types
import Storage.User.Types (UserId)
import Text.Read (readMaybe)
import Workout.Types
import qualified Workout.Update as Update
import qualified Workout.Validation as Validation

createWorkout :: UserId -> Workout -> Store ()
createWorkout uid workout = ExceptT $ case Validation.validateWorkout workout <> storageErrors workout of
    errors@(_ : _) -> pure (Left (InvalidWorkout errors))
    [] -> do
        inserted <-
            T.statement (uid, workout) $
                preparable
                    "INSERT INTO workouts (user_id, id, revision, storage_version, observation, user_data) \
                    \VALUES ($1, $2, $3::text::numeric, 1, $4, $5) ON CONFLICT DO NOTHING RETURNING id"
                    ( (fst >$< param userIdValue)
                        <> (workoutId . snd >$< param workoutIdValue)
                        <> (revisionText . workoutRevision . snd >$< param E.text)
                        <> (toJSON . workoutObservation . snd >$< param E.jsonb)
                        <> (toJSON . workoutUserData . snd >$< param E.jsonb)
                    )
                    (D.rowMaybe (column D.uuid))
        pure (if isJust inserted then Right () else Left WorkoutConflict)

loadWorkout :: UserId -> WorkoutId -> Store (Maybe Workout)
loadWorkout uid wid = ExceptT (selectWorkout False uid wid)

replaceUserData :: UserId -> WorkoutId -> WorkoutRevision -> WorkoutUserData -> Store Workout
replaceUserData uid wid revision = updateWorkout uid wid revision . Update.replaceUserData revision

replaceObservation :: UserId -> WorkoutId -> WorkoutRevision -> WorkoutObservation -> Store Workout
replaceObservation uid wid revision = updateWorkout uid wid revision . Update.replaceObservation revision

-- Lock before applying pure update rules. The write still checks owner, ID and
-- revision in SQL, so stale callers cannot silently overwrite a concurrent edit.
updateWorkout
    :: UserId
    -> WorkoutId
    -> WorkoutRevision
    -> (Workout -> Either Update.UpdateError Workout)
    -> Store Workout
updateWorkout uid wid expected change = ExceptT $ do
    current <- selectWorkout True uid wid
    case current of
        Left err -> pure (Left err)
        Right Nothing -> pure (Left WorkoutNotFound)
        Right (Just workout) -> case change workout of
            Left (Update.RevisionConflict _ _) -> pure (Left WorkoutConflict)
            Left (Update.InvalidWorkout errors) -> pure (Left (InvalidWorkout errors))
            Right next | errors@(_ : _) <- storageErrors next -> pure (Left (InvalidWorkout errors))
            Right next -> do
                count <-
                    T.statement (uid, wid, expected, next) $
                        preparable
                            "UPDATE workouts SET revision = $4::text::numeric, observation = $5, user_data = $6 \
                            \WHERE user_id = $1 AND id = $2 AND revision = $3::text::numeric"
                            ( ((\(u, _, _, _) -> u) >$< param userIdValue)
                                <> ((\(_, w, _, _) -> w) >$< param workoutIdValue)
                                <> ((\(_, _, r, _) -> revisionText r) >$< param E.text)
                                <> ((\(_, _, _, w) -> revisionText (workoutRevision w)) >$< param E.text)
                                <> ((\(_, _, _, w) -> toJSON (workoutObservation w)) >$< param E.jsonb)
                                <> ((\(_, _, _, w) -> toJSON (workoutUserData w)) >$< param E.jsonb)
                            )
                            D.rowsAffected
                pure (if count == 1 then Right next else Left WorkoutConflict)

selectWorkout :: Bool -> UserId -> WorkoutId -> T.Transaction (Either StorageError (Maybe Workout))
selectWorkout lock uid wid =
    sequence
        <$> T.statement
            (uid, wid)
            ( preparable
                ( "SELECT id, revision::text, storage_version, observation, user_data FROM workouts \
                  \WHERE user_id = $1 AND id = $2"
                    <> if lock then " FOR UPDATE" else ""
                )
                ((fst >$< param userIdValue) <> (snd >$< param workoutIdValue))
                (D.rowMaybe workoutRow)
            )

workoutIdValue :: E.Value WorkoutId
workoutIdValue = contramap (\(WorkoutId value) -> value) E.uuid

revisionText :: WorkoutRevision -> Text
revisionText (WorkoutRevision value) = Text.pack (show value)

storageErrors :: Workout -> [Validation.ValidationError]
storageErrors workout =
    jsonErrors "observation" (toJSON (workoutObservation workout))
        <> jsonErrors "userData" (toJSON (workoutUserData workout))

-- Storage v1 shares the existing canonical JSON encoding. Schema/codec changes
-- must explicitly migrate this version; old payloads are never guessed/rebuilt.
workoutRow :: D.Row (Either StorageError Workout)
workoutRow =
    decodeWorkout . WorkoutId
        <$> column D.uuid
        <*> column D.text
        <*> column D.int2
        <*> column D.jsonb
        <*> column D.jsonb

decodeWorkout :: WorkoutId -> Text -> Int16 -> Value -> Value -> Either StorageError Workout
decodeWorkout wid revision version observation userData
    | version /= 1 = Left CorruptWorkout
    | otherwise = case (readMaybe (Text.unpack revision), fromJSON observation, fromJSON userData) of
        (Just r, Success o, Success u) ->
            let workout = Workout wid (WorkoutRevision r) o u
             in if null (Validation.validateWorkout workout) then Right workout else Left CorruptWorkout
        _ -> Left CorruptWorkout
