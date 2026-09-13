{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.Workout.Query (listWorkouts, timeKey) where

import Api.Workout.Types (WorkoutCard)
import Control.Monad.Trans.Except (ExceptT (..))
import Data.Aeson (Result (..), fromJSON)
import Data.Coerce (coerce)
import Data.Int (Int64)
import Data.Profunctor (lmap)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, defaultTimeLocale, formatTime)
import Data.UUID.Types (UUID)
import Data.Vector (Vector)
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import Storage.Types
import Storage.User.Types (UserId (..))
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
            lmap
                ( \(u, q, a, n) ->
                    ( coerce u
                    , timeKey <$> startedFrom q
                    , timeKey <$> startedBefore q
                    , sport q
                    , tag q
                    , timeKey . fst <$> a
                    , snd <$> a
                    , n
                    )
                )
                [TH.vectorStatement|
                    SELECT jsonb_build_object('id', id, 'revision', revision::text,
                        'range', observation->'observationRange', 'userData', user_data,
                        'summary', CASE WHEN observation #>> '{observationSport,type}' = 'cycling'
                            THEN jsonb_build_object('type', 'cyclingSummary', 'data', observation #> '{observationSport,data,cyclingSummary}')
                            ELSE jsonb_build_object('type', 'runningSummary', 'data', observation #> '{observationSport,data,runningSummary}')
                        END) :: jsonb
                    FROM workouts
                    WHERE user_id = $1 :: uuid
                        AND ($2 :: text? IS NULL OR start_key >= ($2 :: text?) :: numeric)
                        AND ($3 :: text? IS NULL OR start_key < ($3 :: text?) :: numeric)
                        AND ($4 :: text? IS NULL OR observation #>> '{observationSport,type}' = $4 :: text?)
                        AND ($5 :: text? IS NULL OR (user_data->'workoutTags') @> jsonb_build_array($5 :: text?))
                        AND ($6 :: text? IS NULL OR (start_key, id) < (($6 :: text?) :: numeric, $7 :: uuid?))
                    ORDER BY start_key DESC, id DESC LIMIT $8 :: int8
                |]
    pure $
        traverse
            ( \value -> case fromJSON value of
                Success card -> Right card
                Error _ -> Left CorruptWorkout
            )
            values
