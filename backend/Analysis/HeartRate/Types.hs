module Analysis.HeartRate.Types
    ( HrssWeighting (..)
    , HrssProfile (..)
    , HrssProfiles (..)
    , CoveragePolicy (..)
    , TimingBasis (..)
    , Coverage (..)
    , LoadAvailability (..)
    , WorkoutLoad (..)
    , HeartRateError (..)
    ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Workout.Types
import Workout.Validation.Types (ValidationError)

-- Explicit algorithm choice; never inferred from a user's identity.
data HrssWeighting = Banister192 | Banister167 deriving (Eq, Show)

data HrssProfile = HrssProfile
    { profileId :: Text
    , profileFrom :: UTCTime
    , profileUntil :: Maybe UTCTime -- exclusive; selection uses workout start
    , restingHeartRate :: HeartRate
    , maximumHeartRate :: HeartRate
    , thresholdHeartRate :: HeartRate
    , hrssWeighting :: HrssWeighting
    }
    deriving (Eq, Show)

data HrssProfiles = HrssProfiles
    { cyclingProfiles :: [HrssProfile]
    , runningProfiles :: [HrssProfile]
    }
    deriving (Eq, Show)

data CoveragePolicy = CoveragePolicy
    { maximumSampleGap :: Duration
    , minimumCoverage :: Double -- fraction in (0,1]
    }
    deriving (Eq, Show)

data TimingBasis = RecordedTimer | ElapsedTimeFallback deriving (Eq, Show)

data Coverage = Coverage
    { activeDuration :: Duration
    , coveredDuration :: Duration
    , longGapDuration :: Duration
    , aboveMaximumDuration :: Duration
    , coverageFraction :: Maybe Double -- Nothing when no active time
    , timingBasis :: TimingBasis
    }
    deriving (Eq, Show)

data LoadAvailability
    = AvailableLoad Double -- observed HRSS, never extrapolated across missing time
    | MissingProfile
    | InsufficientCoverage
    | NoActiveTime
    | ExcludedWorkout
    deriving (Eq, Show)

data WorkoutLoad = WorkoutLoad
    { loadWorkoutId :: WorkoutId
    , loadWorkoutRevision :: WorkoutRevision
    , loadWorkoutStart :: UTCTime
    , loadProfile :: Maybe HrssProfile
    , loadCoverage :: Maybe Coverage
    , observedHrss :: Maybe Double
    , loadAvailability :: LoadAvailability
    }
    deriving (Eq, Show)

data HeartRateError
    = InvalidCoveragePolicy
    | InvalidProfile Text
    | OverlappingProfiles Text Text
    | DuplicateProfileId Text
    | InvalidWorkout WorkoutId [ValidationError]
    | NonFiniteHeartRateResult
    deriving (Eq, Show)
