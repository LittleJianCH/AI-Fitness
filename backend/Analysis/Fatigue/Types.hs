module Analysis.Fatigue.Types
    ( RecordingStatus (..)
    , HistoryDay (..)
    , DailyLoad (..)
    , FatigueConfig (..)
    , InitialState (..)
    , FatiguePoint (..)
    , FatigueHistory (..)
    , FatigueError (..)
    ) where

import Analysis.HeartRate.Types
import Data.Text (Text)
import Data.Time (Day)
import Workout.Types (Workout, WorkoutId)

-- A complete empty day is rest. An incomplete day must not become zero load.
data RecordingStatus = CompleteRecording | IncompleteRecording deriving (Eq, Show)

data HistoryDay = HistoryDay
    { historyDate :: Day
    , recordingStatus :: RecordingStatus
    , dayWorkouts :: [Workout]
    }
    deriving (Eq, Show)

data DailyLoad = DailyLoad
    { loadDate :: Day
    , dayRecordingStatus :: RecordingStatus
    , workoutContributions :: [WorkoutLoad]
    , knownDailyLoad :: Double
    , totalDailyLoad :: Maybe Double
    }
    deriving (Eq, Show)

data FatigueConfig = FatigueConfig
    { fitnessTimeConstant :: Double -- days, [1,36525]
    , fatigueTimeConstant :: Double -- days, [1,fitnessTimeConstant)
    }
    deriving (Eq, Show)

-- Values immediately before the first day, in the same HRSS load scale.
data InitialState = AssumeNoPriorLoad | KnownPriorLoad Double Double deriving (Eq, Show)

data FatiguePoint = FatiguePoint
    { fatigueDate :: Day
    , trainingLoad :: Maybe Double
    , chronicLoad :: Maybe Double
    , acuteLoad :: Maybe Double
    , loadBalance :: Maybe Double -- end-of-day CTL minus ATL
    , historyDays :: Int
    , initialFitnessWeight :: Double
    , initialFatigueWeight :: Double
    }
    deriving (Eq, Show)

data FatigueHistory = FatigueHistory
    { fatigueMethod :: Text
    , heartRateMethod :: Text
    , historyConfig :: FatigueConfig
    , historyCoveragePolicy :: CoveragePolicy
    , historyProfiles :: HrssProfiles
    , historyInitialState :: InitialState
    , dailyLoads :: [DailyLoad]
    , fatiguePoints :: [FatiguePoint]
    }
    deriving (Eq, Show)

data FatigueError
    = HeartRateFailure HeartRateError
    | InvalidFatigueConfig
    | InvalidInitialState
    | EmptyHistory
    | HistoryTooLong
    | DuplicateDay Day
    | DuplicateWorkout WorkoutId
    | WrongWorkoutDay WorkoutId Day Day
    | NonFiniteDailyLoad Day
    deriving (Eq, Show)
