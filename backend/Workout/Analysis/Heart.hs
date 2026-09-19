module Workout.Analysis.Heart (analyseHeart, profiles, powerZones) where

import qualified Analysis.HeartRate.Calculate as Load
import Analysis.HeartRate.Timing (activeRanges, intersectRanges, rangeDuration)
import qualified Analysis.HeartRate.Types as Load
import Data.Coerce (coerce)
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.UUID.Types as UUID
import qualified Data.Vector as V
import Profile.Types
import Workout.Analysis.Series
import Workout.Analysis.Types
import qualified Workout.Sport as Sport
import Workout.Types

profiles :: UserSettings -> Load.HrssProfiles
profiles settings = Load.HrssProfiles (convert bodyCycling) (convert bodyRunning)
  where
    history = V.toList (settingsBodyProfiles settings)
    ends = map (Just . bodyEffectiveFrom) (drop 1 history) <> [Nothing]
    convert sport =
        mapMaybe
            ( \(body, end) -> do
                p <- sportHeartRate (sport body)
                pure
                    ( Load.HrssProfile
                        (UUID.toText (bodyProfileId body))
                        (bodyEffectiveFrom body)
                        end
                        (HeartRate (heartRateResting p))
                        (HeartRate (heartRateMaximum p))
                        (HeartRate (heartRateThreshold p))
                        (case heartRateWeighting p of Exponent192 -> Load.Banister192; Exponent167 -> Load.Banister167)
                    )
            )
            (zip history ends)

analyseHeart :: UserSettings -> Workout -> HeartAnalysis
analyseHeart settings workout = case Load.calculateWorkoutLoad Load.defaultCoveragePolicy (profiles settings) workout of
    Left _ -> blank HeartCalculationUnavailable
    Right load ->
        let status = case Load.loadAvailability load of
                Load.AvailableLoad _ -> HeartLoadAvailable
                Load.MissingProfile -> HeartProfileMissing
                Load.InsufficientCoverage -> HeartCoverageInsufficient
                Load.NoActiveTime -> HeartNoActiveTime
                Load.ExcludedWorkout -> HeartExcluded
            coverage = Load.loadCoverage load
            trimp = do
                p <- Load.loadProfile load
                hrss <- Load.observedHrss load
                let HeartRate resting = Load.restingHeartRate p
                    HeartRate maximumHr = Load.maximumHeartRate p
                    HeartRate threshold = Load.thresholdHeartRate p
                    reserve = (threshold - resting) / (maximumHr - resting)
                    k = case Load.hrssWeighting p of Load.Banister192 -> 1.92; Load.Banister167 -> 1.67
                finite (hrss * 0.6 * reserve * 0.64 * exp (k * reserve))
         in HeartAnalysis
                status
                (Load.observedHrss load)
                trimp
                (coerce . Load.activeDuration <$> coverage)
                (coerce . Load.coveredDuration <$> coverage)
                (coverage >>= Load.coverageFraction)
                usesRecordedTimer
                (maybe V.empty zones (Load.loadProfile load))
  where
    blank status = HeartAnalysis status Nothing Nothing Nothing Nothing Nothing usesRecordedTimer V.empty
    observation = workoutObservation workout
    (timing, ranges) = activeRanges observation
    usesRecordedTimer = timing == Load.RecordedTimer
    readings = V.toList (Sport.heartRate (observationSport observation))
    -- Match the load calculator's left-hold, ten-second gap and resume rules.
    intervals =
        [ (TimeRange (timestamp a) (timestamp b), value a)
        | (a, b) <- zip readings (drop 1 readings)
        , realToFrac (rangeDuration (TimeRange (timestamp a) (timestamp b))) <= (10 :: Double)
        ]
    usable =
        [ (r, hr)
        | (r, (original, hr)) <- intersectRanges [(r, (r, hr)) | (r, hr) <- intervals] ranges
        , rangeStart original == rangeStart r
        ]
    zones p =
        let HeartRate resting = Load.restingHeartRate p
            HeartRate maximumHr = Load.maximumHeartRate p
            boundaries =
                0
                    : [resting + (maximumHr - resting) * fraction | fraction <- [0.5, 0.6, 0.7, 0.8, 0.9]] <> [maximumHr]
            pairs = zip boundaries (map Just (drop 1 boundaries) <> [Nothing])
            duration lo hi =
                sum
                    [ realToFrac (rangeDuration range)
                    | (range, HeartRate hr) <- usable
                    , hr >= lo
                    , maybe True (hr <) hi
                    ]
         in V.fromList [ZoneDuration i lo hi (duration lo hi) | (i, (lo, hi)) <- zip [0 ..] pairs]

powerZones :: Maybe Double -> Samples -> V.Vector ZoneDuration
powerZones Nothing _ = V.empty
powerZones (Just ftp) xs
    | any (\x -> isNaN x || isInfinite x) boundaries = V.empty
    | otherwise =
        V.fromList
            [ZoneDuration i lo hi (sum (map (inside lo hi) spans)) | (i, (lo, hi)) <- zip [1 ..] pairs]
  where
    boundaries = map (* ftp) [0, 0.55, 0.75, 0.90, 1.05, 1.20, 1.50]
    pairs = zip boundaries (map Just (drop 1 boundaries) <> [Nothing])
    spans = segments 5 xs
    inside lo hi (Segment a b x y)
        | x == y = if x >= lo && maybe True (x <) hi then b - a else 0
        | otherwise =
            (b - a) * (max 0 (min (fromMaybe (max x y) hi) (max x y) - max lo (min x y)) / abs (y - x))
