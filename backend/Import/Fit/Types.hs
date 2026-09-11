module Import.Fit.Types
    ( FitError (..)
    , FitSport (..)
    , FitSession (..)
    , FitRecord (..)
    , DecodedFit (..)
    ) where

import Data.Vector (Vector)
import Workout.Validation.Types (ValidationError)

data FitError
    = InvalidFit
    | UnsupportedFit
    | MissingFitTime
    | FitResourceLimit
    | FitAdapterFailure
    | FitFileUnreadable
    | InvalidFitObservation [ValidationError]
    deriving (Eq, Show)

-- SDK-scaled values; timestamps are absolute seconds from the FIT epoch.
-- These are adapter values, not canonical domain types.
data FitSport = FitCycling | FitRunning deriving (Eq, Show)

data FitSession = FitSession
    { fitSport :: FitSport
    , fitStart :: Double
    , fitEnd :: Double
    , fitElapsed :: Maybe Double
    , fitTimer :: Maybe Double
    , fitTotalDistance :: Maybe Double
    }
    deriving (Eq, Show)

data FitRecord = FitRecord
    { fitTimestamp :: Double
    , fitHeartRate :: Maybe Double
    , fitPower :: Maybe Double
    , fitSpeed :: Maybe Double
    , fitDistance :: Maybe Double
    , fitCadence :: Maybe Double -- cycles/min, including fractional cadence
    , fitAltitude :: Maybe Double -- metres
    , fitLatitude :: Maybe Double -- FIT semicircles
    , fitLongitude :: Maybe Double -- FIT semicircles
    }
    deriving (Eq, Show)

data DecodedFit = DecodedFit FitSession (Vector FitRecord)
    deriving (Eq, Show)
