{-# LANGUAGE OverloadedStrings #-}

module Storage.Workout.Query (listWorkouts, timeKey) where

import Api.Workout.Types (WorkoutCard)
import Control.Monad.Trans.Except (ExceptT (..))
import Data.Aeson (Result (..), fromJSON)
import Data.Functor.Contravariant ((>$<))
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, defaultTimeLocale, formatTime)
import Data.UUID.Types (UUID)
import Data.Vector (Vector)
import qualified Hasql.Decoders as D
import qualified Hasql.Encoders as E
import Hasql.Statement (preparable)
import qualified Hasql.Transaction as T
import Storage.Codec
import Storage.Types
import Storage.User.Types (UserId)
import Storage.Workout.Types

-- Decimal calendar key, not an epoch timestamp: this only supplies UTC ordering
-- and retains the same precision as the canonical timestamp's decimal seconds.
timeKey :: UTCTime -> Text
timeKey = Text.pack . formatTime defaultTimeLocale "%Y%m%d%H%M%S%Q"

listWorkouts
    :: UserId -> WorkoutFilter -> Maybe (UTCTime, UUID) -> Int64 -> Store (Vector WorkoutCard)
listWorkouts uid query after limit = ExceptT $ do
    values <-
        T.statement (uid, query, after, limit) $
            preparable
                "SELECT jsonb_build_object('id', id, 'revision', revision::text, \
                \'range', observation->'observationRange', 'userData', user_data, \
                \'summary', CASE WHEN observation #>> '{observationSport,type}' = 'cycling' \
                \THEN jsonb_build_object('type', 'cyclingSummary', 'data', observation #> '{observationSport,data,cyclingSummary}') \
                \ELSE jsonb_build_object('type', 'runningSummary', 'data', observation #> '{observationSport,data,runningSummary}') END) \
                \FROM workouts WHERE user_id = $1 AND ($2::text IS NULL OR start_key >= $2::text::numeric) \
                \AND ($3::text IS NULL OR start_key < $3::text::numeric) \
                \AND ($4::text IS NULL OR observation #>> '{observationSport,type}' = $4) \
                \AND ($5::text IS NULL OR (user_data->'workoutTags') @> jsonb_build_array($5::text)) \
                \AND ($6::text IS NULL OR (start_key, id) < ($6::text::numeric, $7)) \
                \ORDER BY start_key DESC, id DESC LIMIT $8"
                ( ((\(u, _, _, _) -> u) >$< param userIdValue)
                    <> ((\(_, q, _, _) -> timeKey <$> startedFrom q) >$< E.param (E.nullable E.text))
                    <> ((\(_, q, _, _) -> timeKey <$> startedBefore q) >$< E.param (E.nullable E.text))
                    <> ((\(_, q, _, _) -> sport q) >$< E.param (E.nullable E.text))
                    <> ((\(_, q, _, _) -> tag q) >$< E.param (E.nullable E.text))
                    <> ((\(_, _, a, _) -> timeKey . fst <$> a) >$< E.param (E.nullable E.text))
                    <> ((\(_, _, a, _) -> snd <$> a) >$< E.param (E.nullable E.uuid))
                    <> ((\(_, _, _, n) -> n) >$< param E.int8)
                )
                (D.rowVector (column D.jsonb))
    pure $
        traverse
            (\value -> case fromJSON value of Success card -> Right card; Error _ -> Left CorruptWorkout)
            values
