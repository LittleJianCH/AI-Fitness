{-# LANGUAGE OverloadedStrings #-}

module HeartRateTests (cases) where

import Analysis.HeartRate.Calculate
import Analysis.HeartRate.Types
import AnalysisFixtures
import Data.Either (isLeft)
import Data.Maybe (fromMaybe)
import Data.Time (addUTCTime)
import qualified Data.Vector as V
import Workout.Empty
import Workout.Types

cases :: [(String, Bool)]
cases =
    [
        ( "zero active time is known without a heart-rate profile"
        , case calculateWorkoutLoad
            defaultCoveragePolicy
            (HrssProfiles [] [])
            (withEvents [(0, TimerStopped)] ride) of
            Right r -> loadAvailability r == NoActiveTime
            _ -> False
        )
    ,
        ( "complete subsecond coverage meets a strict full-coverage policy"
        , case calculateWorkoutLoad (CoveragePolicy (Duration 10) 1) profiles subsecond of
            Right WorkoutLoad {loadAvailability = AvailableLoad n} -> near (100 / 3600) n
            _ -> False
        )
    , ("HRSS one hour at threshold is 100", scoreNear 100 ride)
    , ("HRSS running uses the same integration", scoreNear 100 run)
    ,
        ( "HRSS resting heart rate is valid zero load"
        , scoreNear 0 (withSamples [(t, 60) | t <- [0, 10 .. 3600]] ride)
        )
    ,
        ( "HRSS below resting contributes zero"
        , scoreNear 0 (withSamples [(t, 50) | t <- [0, 10 .. 3600]] ride)
        )
    ,
        ( "HRSS maximum has a larger dose"
        , maybe False (> 100) (loadScore (withSamples [(t, 200) | t <- [0, 10 .. 3600]] ride))
        )
    ,
        ( "HRSS integrates nonlinear intensity instead of mean HR"
        , maybe
            False
            (near mixedGolden)
            ( observedHrss
                =<< eitherMaybe (calculateWorkoutLoad (CoveragePolicy (Duration 1800) 1) profiles mixed)
            )
        )
    , ("HRSS explicit alternate weighting", profileScore Banister167 > profileScore Banister192)
    ,
        ( "HRSS irregular sampling uses duration not sample count"
        , maybe False (near (100 / 3600 * 10)) (loadScore irregular)
        )
    , ("pause does not earn load", scoreNear 50 paused)
    ,
        ( "pause coverage denominator is active duration"
        , coverageSatisfies
            ( \c ->
                activeDuration c == Duration 1800 && coverageFraction c == Just 1 && timingBasis c == RecordedTimer
            )
            paused
        )
    ,
        ( "missing timer uses labelled elapsed fallback"
        , coverageSatisfies ((== ElapsedTimeFallback) . timingBasis) ride
        )
    , ("duplicate starts do not discard valid sample time", scoreNear (100 / 3600 * 10) duplicateStarts)
    ,
        ( "first start later than range omits leading stopped time"
        , scoreNear 50 (withEvents [(1800, TimerStarted)] ride)
        )
    ,
        ( "first stop implies activity before that stop"
        , scoreNear 50 (withEvents [(1800, TimerStopped)] ride)
        )
    ,
        ( "stopped entire workout yields no active time"
        , availability (withEvents [(0, TimerStopped)] ride) == Just NoActiveTime
        )
    ,
        ( "reading from before resume cannot cover resumed time"
        , coverageSatisfies ((== Duration 10) . coveredDuration) staleResume
        )
    ,
        ( "samples after stop are ignored"
        , scoreNear
            50
            (withSamples ([(t, 180) | t <- [0, 10 .. 1800]] ++ [(t, 200) | t <- [1810, 1820 .. 3600]]) paused)
        )
    , ("empty samples are unknown", availability (withSamples [] ride) == Just InsufficientCoverage)
    ,
        ( "single sample is not extrapolated"
        , availability (withSamples [(0, 180)] ride) == Just InsufficientCoverage
        )
    ,
        ( "last reading is not held to end"
        , coverageSatisfies
            ((== Duration 3590) . coveredDuration)
            (withSamples [(t, 180) | t <- [0, 10 .. 3590]] ride)
        )
    ,
        ( "large gaps are not interpolated or zero-filled"
        , coverageSatisfies
            (\c -> longGapDuration c == Duration 3600 && coveredDuration c == Duration 0)
            (withSamples [(0, 180), (3600, 180)] ride)
        )
    ,
        ( "above maximum is excluded and reported"
        , coverageSatisfies
            (\c -> aboveMaximumDuration c == Duration 3600 && coveredDuration c == Duration 0)
            (withSamples [(t, 210) | t <- [0, 10 .. 3600]] ride)
        )
    ,
        ( "accepted partial coverage retains observed load without scaling"
        , scoreNear (100 * 3590 / 3600) (withSamples [(t, 180) | t <- [0, 10 .. 3590]] ride)
        )
    ,
        ( "strict coverage rejects partial result"
        , case calculateWorkoutLoad
            (CoveragePolicy (Duration 10) 1)
            profiles
            (withSamples [(t, 180) | t <- [0, 10 .. 3590]] ride) of
            Right r -> loadAvailability r == InsufficientCoverage
            _ -> False
        )
    ,
        ( "malformed timestamps rejected"
        , isLeft
            (calculateWorkoutLoad defaultCoveragePolicy profiles (withSamples [(10, 180), (0, 180)] ride))
        )
    ,
        ( "invalid canonical sample rejected"
        , isLeft (calculateWorkoutLoad defaultCoveragePolicy profiles (withSamples [(0, 0 / 0)] ride))
        )
    ,
        ( "missing profile is unknown"
        , case calculateWorkoutLoad defaultCoveragePolicy (HrssProfiles [] []) ride of
            Right r -> loadAvailability r == MissingProfile
            _ -> False
        )
    ,
        ( "expired profile is not reused"
        , case calculateWorkoutLoad
            defaultCoveragePolicy
            (HrssProfiles [profile {profileUntil = Just epoch}] [])
            ride of
            Right r -> loadAvailability r == MissingProfile
            _ -> False
        )
    ,
        ( "profile start boundary selects new snapshot"
        , case calculateWorkoutLoad defaultCoveragePolicy changedProfiles ride of
            Right r -> (profileId <$> loadProfile r) == Just "new"
            _ -> False
        )
    ,
        ( "profile chosen per sport"
        , case calculateWorkoutLoad defaultCoveragePolicy (profiles {runningProfiles = []}) run of
            Right r -> loadAvailability r == MissingProfile
            _ -> False
        )
    ,
        ( "profile selection uses start when session crosses boundary"
        , case calculateWorkoutLoad defaultCoveragePolicy changedProfiles (shiftWorkout (-600) ride) of
            Right r -> (profileId <$> loadProfile r) == Just "old"
            _ -> False
        )
    ,
        ( "overlapping profiles rejected"
        , isLeft (validateProfiles (HrssProfiles [profile, profile {profileId = "second"}] []))
        )
    ,
        ( "duplicate profile ids rejected"
        , isLeft
            ( validateProfiles
                (HrssProfiles [profile {profileUntil = Just epoch}, profile {profileFrom = epoch}] [])
            )
        )
    ,
        ( "invalid threshold rejected"
        , isLeft (validateProfiles (HrssProfiles [profile {thresholdHeartRate = HeartRate 60}] []))
        )
    , ("non-finite settings rejected", isLeft (validatePolicy (CoveragePolicy (Duration (1 / 0)) 1)))
    , ("coverage fraction bounded", isLeft (validatePolicy (CoveragePolicy (Duration 10) 0)))
    ,
        ( "canonical summaries not used as fallback"
        , availability (withSamples [] ride) == Just InsufficientCoverage
        )
    ]

-- Independent values from the normalised exponential-dose equation.
mixedGolden :: Double
mixedGolden = 50 + 25 * exp (-(1.92 * 60 / 140))

scoreNear :: Double -> Workout -> Bool
scoreNear n = nearMaybe n . loadScore
loadScore :: Workout -> Maybe Double
loadScore w = do
    result <- eitherMaybe (calculateWorkoutLoad defaultCoveragePolicy profiles w)
    case loadAvailability result of AvailableLoad n -> Just n; _ -> Nothing
availability :: Workout -> Maybe LoadAvailability
availability = fmap loadAvailability . eitherMaybe . calculateWorkoutLoad defaultCoveragePolicy profiles
coverageSatisfies :: (Coverage -> Bool) -> Workout -> Bool
coverageSatisfies f w =
    maybe False f (loadCoverage =<< eitherMaybe (calculateWorkoutLoad defaultCoveragePolicy profiles w))
profileScore :: HrssWeighting -> Double
profileScore weighting = fromMaybe (-1) $ do
    r <-
        eitherMaybe
            ( calculateWorkoutLoad
                defaultCoveragePolicy
                (HrssProfiles [profile {hrssWeighting = weighting}] [])
                (withSamples [(t, 120) | t <- [0, 10 .. 3600]] ride)
            )
    observedHrss r

subsecond :: Workout
subsecond =
    ride
        { workoutObservation =
            o
                { observationRange = TimeRange epoch (addUTCTime 1 epoch)
                , observationSport =
                    Cycling
                        emptyCycling
                            { cyclingMotion =
                                emptyMotion
                                    { motionHeartRate =
                                        V.fromList [Timed (addUTCTime (fromInteger n / 10) epoch) (HeartRate 180) | n <- [0 .. 10]]
                                    }
                            }
                }
        }
  where
    o = workoutObservation ride
