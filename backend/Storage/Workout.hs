{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.Workout
    ( createWorkout
    , loadWorkout
    , replaceUserData
    , replaceObservation
    , updateWorkout
    , saveUpdated
    , revisionText
    ) where

import Api.Workout.Codec ()
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Aeson (Result (..), Value, fromJSON, toJSON)
import Data.Coerce (coerce)
import Data.Int (Int16)
import Data.Maybe (isJust)
import Data.Profunctor (dimap, lmap)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.UUID.Types (UUID)
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import Storage.Codec
import Storage.Types
import Storage.User.Types (UserId (..))
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
                lmap
                    ( \(u, w) ->
                        ( coerce u
                        , coerce (workoutId w)
                        , revisionText (workoutRevision w)
                        , toJSON (workoutObservation w)
                        , toJSON (workoutUserData w)
                        )
                    )
                    [TH.maybeStatement|
                        INSERT INTO workouts (user_id, id, revision, storage_version, observation, user_data)
                        VALUES ($1 :: uuid, $2 :: uuid, ($3 :: text) :: numeric, 1, $4 :: jsonb, $5 :: jsonb)
                        ON CONFLICT DO NOTHING RETURNING id :: uuid
                    |]
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
            Right next -> runExceptT (saveUpdated uid expected next)

-- The caller already resolved the owner and revision in the same transaction.
-- Keep the final compare-and-swap even when an import reuses its loaded workout.
saveUpdated :: UserId -> WorkoutRevision -> Workout -> Store Workout
saveUpdated uid expected next = ExceptT $ case Validation.validateWorkout next <> storageErrors next of
    errors@(_ : _) -> pure (Left (InvalidWorkout errors))
    [] -> do
        count <-
            T.statement (uid, workoutId next, expected, next) $
                lmap
                    ( \(u, w, r, n) ->
                        ( coerce u
                        , coerce w
                        , revisionText r
                        , revisionText (workoutRevision n)
                        , toJSON (workoutObservation n)
                        , toJSON (workoutUserData n)
                        )
                    )
                    [TH.rowsAffectedStatement|
                        UPDATE workouts SET revision = ($4 :: text) :: numeric,
                            observation = $5 :: jsonb, user_data = $6 :: jsonb
                        WHERE user_id = $1 :: uuid AND id = $2 :: uuid
                          AND revision = ($3 :: text) :: numeric
                    |]
        pure (if count == 1 then Right next else Left WorkoutConflict)

selectWorkout :: Bool -> UserId -> WorkoutId -> T.Transaction (Either StorageError (Maybe Workout))
selectWorkout lock uid wid =
    sequence
        <$> T.statement
            (uid, wid)
            (dimap coerce (fmap decodeWorkout) statement)
  where
    -- Both variants are checked at compile time, including the lock clause.
    statement =
        if lock
            then
                [TH.maybeStatement|
                    SELECT id :: uuid, revision :: text, storage_version :: int2,
                           observation :: jsonb, user_data :: jsonb
                    FROM workouts WHERE user_id = $1 :: uuid AND id = $2 :: uuid FOR UPDATE
                |]
            else
                [TH.maybeStatement|
                    SELECT id :: uuid, revision :: text, storage_version :: int2,
                           observation :: jsonb, user_data :: jsonb
                    FROM workouts WHERE user_id = $1 :: uuid AND id = $2 :: uuid
                |]

revisionText :: WorkoutRevision -> Text
revisionText (WorkoutRevision value) = Text.pack (show value)

storageErrors :: Workout -> [Validation.ValidationError]
storageErrors workout =
    jsonErrors "observation" (toJSON (workoutObservation workout))
        <> jsonErrors "userData" (toJSON (workoutUserData workout))

-- Storage v1 shares the existing canonical JSON encoding. Schema/codec changes
-- must explicitly migrate this version; old payloads are never guessed/rebuilt.
decodeWorkout :: (UUID, Text, Int16, Value, Value) -> Either StorageError Workout
decodeWorkout (wid, revision, version, observation, userData)
    | version /= 1 = Left CorruptWorkout
    | otherwise = case (readMaybe (Text.unpack revision), fromJSON observation, fromJSON userData) of
        (Just r, Success o, Success u) ->
            let workout = Workout (WorkoutId wid) (WorkoutRevision r) o u
             in if null (Validation.validateWorkout workout) then Right workout else Left CorruptWorkout
        _ -> Left CorruptWorkout
