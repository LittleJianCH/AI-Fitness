module Import.Fit.Normalize (normalizeWorkout) where

import Data.Time (UTCTime (..), addUTCTime, fromGregorian)
import qualified Data.Vector as V
import Import.Fit.Types
import Workout.Empty
import Workout.Types
import Workout.Validation (validateObservation)

normalizeWorkout :: DecodedFit -> Either FitError WorkoutObservation
normalizeWorkout (DecodedFit session records)
    | any invalidTime (fitStart session : fitEnd session : V.toList (fitTimestamp <$> records)) =
        Left MissingFitTime
    | otherwise = case validateObservation observation of
        [] -> Right observation
        errors -> Left (InvalidFitObservation errors)
  where
    observation =
        WorkoutObservation
            { observationRange = TimeRange (utc (fitStart session)) (utc (fitEnd session))
            , observationSport = case fitSport session of
                FitCycling ->
                    Cycling
                        emptyCycling
                            { cyclingMotion = motion
                            , cyclingCadence = series CyclingCadence fitCadence
                            , cyclingSummary = reportedOnly emptyCyclingSummary {cyclingCommonSummary = summary}
                            }
                FitRunning ->
                    Running
                        emptyRunning
                            { runningMotion = motion
                            , runningCadence = series (RunningCadence . (* 2)) fitCadence
                            , runningSummary = reportedOnly emptyRunningSummary {runningCommonSummary = summary}
                            }
            , observationEvents = V.empty
            , observationCoursePoints = V.empty
            , observationAthlete = emptyAthlete
            , observationExtensions = V.empty
            , observationDataIssues = V.empty
            }
    motion =
        emptyMotion
            { motionHeartRate = series HeartRate fitHeartRate
            , motionPower = series Power fitPower
            , motionSpeed = series Speed fitSpeed
            , motionDistance = series Distance fitDistance
            , motionAltitude = series Altitude fitAltitude
            , motionPosition =
                series
                    id
                    ( \record ->
                        Position . degrees
                            <$> fitLatitude record
                            <*> (degrees <$> fitLongitude record)
                    )
            }
    summary =
        emptyCommonSummary
            { summaryElapsedTime = Duration <$> fitElapsed session
            , summaryTimerTime = Duration <$> fitTimer session
            , summaryDistance = Distance <$> fitTotalDistance session
            }
    series constructor field =
        V.mapMaybe
            (\record -> Timed (utc (fitTimestamp record)) . constructor <$> field record)
            records

-- FIT cadence is cycles/min; RunningCadence counts both feet (steps/min).
-- Coordinate conversion occurs exactly once, at this canonical boundary.
degrees :: Double -> Double
degrees semicircles = semicircles * (180 / 2147483648)

-- FIT values below 0x10000000 are device-relative time, not UTC instants.
invalidTime :: Double -> Bool
invalidTime x = isNaN x || isInfinite x || x < 268435456 || x >= 4294967295

utc :: Double -> UTCTime
utc seconds = addUTCTime (realToFrac seconds) (UTCTime (fromGregorian 1989 12 31) 0)
