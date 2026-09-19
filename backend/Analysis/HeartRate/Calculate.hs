{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

module Analysis.HeartRate.Calculate (calculateWorkoutLoad, validateProfiles, validatePolicy, defaultCoveragePolicy, hrssMethod) where

import Analysis.HeartRate.Timing
import Analysis.HeartRate.Types
import Control.Monad (unless)
import Data.List (find, sortOn)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (diffUTCTime)
import qualified Data.Vector as V
import qualified Workout.Sport as Sport
import Workout.Types
import Workout.Validation (validateWorkout)

hrssMethod :: Text
hrssMethod = "hrss.time-integral.v1"

defaultCoveragePolicy :: CoveragePolicy
defaultCoveragePolicy = CoveragePolicy (Duration 10) 0.95

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

validatePolicy :: CoveragePolicy -> Either HeartRateError ()
validatePolicy (CoveragePolicy (Duration gap) fraction) =
    unless
        (finite gap && gap > 0 && finite fraction && fraction > 0 && fraction <= 1)
        (Left InvalidCoveragePolicy)

validateProfiles :: HrssProfiles -> Either HeartRateError ()
validateProfiles profiles = do
    validateList (cyclingProfiles profiles)
    validateList (runningProfiles profiles)
  where
    validateList xs = do
        mapM_ validateProfile xs
        _ <- foldl' unique (Right Set.empty) xs
        mapM_ disjoint (zip ordered (drop 1 ordered))
      where
        ordered = sortOn profileFrom xs
        unique acc p = do
            seen <- acc
            if Set.member (profileId p) seen
                then Left (DuplicateProfileId (profileId p))
                else Right (Set.insert (profileId p) seen)
        disjoint (a, b) =
            unless
                (maybe False (<= profileFrom b) (profileUntil a))
                (Left (OverlappingProfiles (profileId a) (profileId b)))
    validateProfile p =
        let HeartRate resting = restingHeartRate p
            HeartRate maximumHr = maximumHeartRate p
            HeartRate threshold = thresholdHeartRate p
            ratio = (threshold - resting) / (maximumHr - resting)
         in unless
                ( not (Text.null (Text.strip (profileId p)))
                    && all finite [resting, maximumHr, threshold, ratio]
                    && resting > 0
                    && resting < threshold
                    && threshold <= maximumHr
                    && ratio > 0
                    && maybe True (> profileFrom p) (profileUntil p)
                )
                (Left (InvalidProfile (profileId p)))

calculateWorkoutLoad
    :: CoveragePolicy -> HrssProfiles -> Workout -> Either HeartRateError WorkoutLoad
calculateWorkoutLoad policy profiles workout = do
    validatePolicy policy
    validateProfiles profiles
    unless (null errors) (Left (InvalidWorkout (workoutId workout) errors))
    if statisticsInclusion (workoutUserData workout) == ExcludeFromStatistics
        then pure (base {loadAvailability = ExcludedWorkout})
        else
            if null ranges
                then
                    pure
                        base
                            { loadCoverage = Just (Coverage (Duration 0) (Duration 0) (Duration 0) (Duration 0) Nothing basis)
                            , observedHrss = Just 0
                            , loadAvailability = NoActiveTime
                            }
                else case find applicable candidates of
                    Nothing -> pure base
                    Just profile -> calculate profile
  where
    errors = validateWorkout workout
    observation = workoutObservation workout
    sport = observationSport observation
    start = rangeStart (observationRange observation)
    (basis, ranges) = activeRanges observation
    candidates = case sport of Cycling _ -> cyclingProfiles profiles; Running _ -> runningProfiles profiles
    applicable p = profileFrom p <= start && maybe True (start <) (profileUntil p)
    base =
        WorkoutLoad
            (workoutId workout)
            (workoutRevision workout)
            start
            Nothing
            Nothing
            Nothing
            MissingProfile
    calculate profile = do
        let samples = V.toList (Sport.heartRate sport)
            Duration maxGap = maximumSampleGap policy
            HeartRate maximumHr = maximumHeartRate profile
            pairs =
                [ ( TimeRange (timestamp a) (timestamp b)
                  , (value a, realToFrac (diffUTCTime (timestamp b) (timestamp a)) > maxGap)
                  )
                | (a, b) <- zip samples (drop 1 samples)
                ]
            -- Do not hold a pre-pause reading into a resumed interval. A fresh
            -- sample at/after that interval's start is required.
            usable =
                [ (r, if rangeStart original < rangeStart r then Nothing else Just (hr, gap))
                | (r, (original, hr, gap)) <- intersectRanges [(r, (r, hr, gap)) | (r, (hr, gap)) <- pairs] ranges
                ]
            step (!coveredSoFar, !longGaps, !aboveSoFar, !scoreSoFar) (r, reading) =
                let dt = rangeDuration r
                 in case reading of
                        Nothing -> (coveredSoFar, longGaps, aboveSoFar, scoreSoFar)
                        Just (_, True) -> (coveredSoFar, longGaps + dt, aboveSoFar, scoreSoFar)
                        Just (HeartRate hr, False)
                            | hr > maximumHr -> (coveredSoFar, longGaps, aboveSoFar + dt, scoreSoFar)
                            | otherwise ->
                                (coveredSoFar + dt, longGaps, aboveSoFar, scoreSoFar + realToFrac dt / 36 * relativeDose profile hr)
            (covered, gaps, above, score) = foldl' step (0, 0, 0, 0) usable
            active = sum (rangeDuration <$> ranges)
            fraction = if active > 0 then Just (fromRational (toRational covered / toRational active)) else Nothing
            coverage =
                Coverage
                    (Duration (realToFrac active))
                    (Duration (realToFrac covered))
                    (Duration (realToFrac gaps))
                    (Duration (realToFrac above))
                    fraction
                    basis
            availability
                | active == 0 = NoActiveTime
                | maybe False (>= minimumCoverage policy) fraction = AvailableLoad score
                | otherwise = InsufficientCoverage
        unless
            (all finite [realToFrac active, realToFrac covered, realToFrac gaps, realToFrac above, score])
            (Left NonFiniteHeartRateResult)
        pure
            base
                { loadProfile = Just profile
                , loadCoverage = Just coverage
                , observedHrss = Just score
                , loadAvailability = availability
                }

-- Normalise the exponential TRIMP dose against one hour at threshold. The
-- multiplicative TRIMP coefficient cancels. Ratios below resting HR contribute
-- zero; readings above configured maximum are excluded before this function.
relativeDose :: HrssProfile -> Double -> Double
relativeDose p hr =
    let HeartRate resting = restingHeartRate p
        HeartRate maximumHr = maximumHeartRate p
        HeartRate threshold = thresholdHeartRate p
        reserve = max 0 ((hr - resting) / (maximumHr - resting))
        thresholdReserve = (threshold - resting) / (maximumHr - resting)
        k = case hrssWeighting p of Banister192 -> 1.92; Banister167 -> 1.67
     in reserve / thresholdReserve * exp (k * (reserve - thresholdReserve))
