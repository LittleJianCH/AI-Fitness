{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Analysis.Fatigue.Request
    ( CalendarDay (..)
    , TrainingHistoryRequest (..)
    , TrainingHistory (..)
    , TrainingDay (..)
    , validateRequest
    , calculateHistory
    ) where

import Analysis.Fatigue.Calculate (analyseFatigue, defaultFatigueConfig)
import Analysis.Fatigue.Types
import Analysis.HeartRate.Calculate (defaultCoveragePolicy)
import Data.Bifunctor (first)
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time
    ( Day
    , UTCTime (..)
    , addDays
    , defaultTimeLocale
    , diffUTCTime
    , parseTimeM
    , utctDay
    )
import Data.Vector (Vector)
import qualified Data.Vector as V
import GHC.Generics (Generic)
import Profile.Types (SettingsRevision, UserSettings, settingsRevision)
import Workout.Analysis.Heart (profiles)
import Workout.Types

-- The caller supplies civil-day boundaries from its timezone-aware calendar.
-- They are explicit analysis inputs, not silently inferred from a UTC offset.
data CalendarDay = CalendarDay
    { calendarDate :: Text
    , calendarStart :: UTCTime
    , calendarEnd :: UTCTime
    , calendarRecordingComplete :: Bool
    }
    deriving (Eq, Show, Generic)

data TrainingHistoryRequest = TrainingHistoryRequest
    { historyCalendar :: Vector CalendarDay
    , historyAssumeNoPriorLoad :: Bool
    , historyPriorFitness :: Maybe Double
    , historyPriorFatigue :: Maybe Double
    }
    deriving (Eq, Show, Generic)

data TrainingHistory = TrainingHistory
    { trainingMethod :: Text
    , trainingSettingsRevision :: SettingsRevision
    , trainingDays :: Vector TrainingDay
    , trainingInitialFitness :: Double
    , trainingInitialFatigue :: Double
    }
    deriving (Eq, Show, Generic)

data TrainingDay = TrainingDay
    { trainingCalendar :: CalendarDay
    , trainingKnownLoad :: Double
    , trainingTotalLoad :: Maybe Double
    , trainingFitness :: Maybe Double
    , trainingFatigue :: Maybe Double
    , trainingBalance :: Maybe Double
    , trainingWorkoutCount :: Int
    , trainingInitialFitnessWeight :: Double
    }
    deriving (Eq, Show, Generic)

validateRequest :: TrainingHistoryRequest -> Either Text [(Day, CalendarDay)]
validateRequest request = do
    require (not (V.null entries) && V.length entries <= 366) "Supply between 1 and 366 calendar days"
    days <- traverse parse (V.toList entries)
    require
        ( and
            [addDays 1 a == b && calendarEnd x == calendarStart y | ((a, x), (b, y)) <- zip days (drop 1 days)]
        )
        "Calendar days must be consecutive and contiguous"
    _ <- initialState request
    pure days
  where
    entries = historyCalendar request
    parse entry = do
        day <-
            maybe
                (Left "Calendar date must use YYYY-MM-DD")
                Right
                (parseTimeM True defaultTimeLocale "%Y-%m-%d" (Text.unpack (calendarDate entry)) :: Maybe Day)
        require (Text.length (calendarDate entry) == 10) "Calendar date must use YYYY-MM-DD"
        let duration = diffUTCTime (calendarEnd entry) (calendarStart entry)
        require
            ( duration >= 18 * 3600
                && duration <= 30 * 3600
                && plausibleMidnight day (calendarStart entry)
                && plausibleMidnight (addDays 1 day) (calendarEnd entry)
            )
            "Invalid civil-day boundaries"
        pure (day, entry)
    -- Civil midnight can be at UTC-12 through UTC+14. Validate both ends;
    -- comparing UTC dates alone admits boundaries displaced by almost 48 hours.
    plausibleMidnight day time =
        let offset = diffUTCTime time (UTCTime day 0)
         in offset >= -(14 * 3600) && offset <= 12 * 3600

initialState :: TrainingHistoryRequest -> Either Text InitialState
initialState request = case (historyAssumeNoPriorLoad request, historyPriorFitness request, historyPriorFatigue request) of
    (True, Nothing, Nothing) -> Right AssumeNoPriorLoad
    (False, Just fitness, Just fatigue)
        | all (\x -> x >= 0 && not (isNaN x || isInfinite x)) [fitness, fatigue] ->
            Right (KnownPriorLoad fitness fatigue)
    _ -> Left "Explicitly choose zero prior load or supply both initial fitness and fatigue"

calculateHistory
    :: UserSettings -> TrainingHistoryRequest -> [Workout] -> Either Text TrainingHistory
calculateHistory settings request workouts = do
    days <- validateRequest request
    initial <- initialState request
    let belongs entry workout =
            let start = rangeStart (observationRange (workoutObservation workout))
             in calendarStart entry <= start && start < calendarEnd entry
        localDay time =
            maybe
                (utctDay time)
                fst
                (find (\(_, entry) -> calendarStart entry <= time && time < calendarEnd entry) days)
        makeDay (day, entry) =
            HistoryDay
                day
                (if calendarRecordingComplete entry then CompleteRecording else IncompleteRecording)
                (filter (belongs entry) workouts)
    require
        (all (\w -> any (\(_, entry) -> belongs entry w) days) workouts)
        "Workout outside requested calendar"
    result <-
        first (const "Training load cannot be calculated from the supplied history") $
            analyseFatigue
                localDay
                defaultCoveragePolicy
                (profiles settings)
                defaultFatigueConfig
                initial
                (map makeDay days)
    let convert (_, calendar) load point =
            TrainingDay
                calendar
                (knownDailyLoad load)
                (totalDailyLoad load)
                (chronicLoad point)
                (acuteLoad point)
                (loadBalance point)
                (length (workoutContributions load))
                (initialFitnessWeight point)
        (fitness, fatigue) = case initial of AssumeNoPriorLoad -> (0, 0); KnownPriorLoad ctl atl -> (ctl, atl)
    pure
        ( TrainingHistory
            (fatigueMethod result)
            (settingsRevision settings)
            (V.fromList (zipWith3 convert days (dailyLoads result) (fatiguePoints result)))
            fitness
            fatigue
        )

require :: Bool -> Text -> Either Text ()
require True _ = Right ()
require False message = Left message
