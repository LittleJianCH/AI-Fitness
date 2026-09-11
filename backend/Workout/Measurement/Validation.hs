{-# LANGUAGE OverloadedStrings #-}

module Workout.Measurement.Validation
    ( check
    , positive
    , ValidValue (..)
    , optional
    , rangeErrors
    , inside
    , validateTimeSeries
    , prefix
    , series
    , statistics
    , summaries
    , cumulative
    , events
    , extensions
    , laps
    , calculatedRevisionErrors
    ) where

import Data.List (nub)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Time
import qualified Data.Vector as V
import Workout.Identity.Types
import Workout.Measurement.Types
import Workout.Validation.Types

check :: Text -> Text -> Bool -> [ValidationError]
check field message ok = [ValidationError field message | not ok]

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

nonnegative :: Double -> Bool
nonnegative x = finite x && x >= 0

positive :: Double -> Bool
positive x = finite x && x > 0

bounded :: Double -> Double -> Double -> Bool
bounded lo hi x = finite x && lo <= x && x <= hi

-- Internal capability for traversing typed measurements without erasing units.
class ValidValue a where
    validValue :: a -> Bool

instance ValidValue HeartRate where validValue (HeartRate x) = positive x
instance ValidValue Power where validValue (Power x) = nonnegative x
instance ValidValue CyclingCadence where validValue (CyclingCadence x) = nonnegative x
instance ValidValue RunningCadence where validValue (RunningCadence x) = nonnegative x
instance ValidValue Speed where validValue (Speed x) = nonnegative x
instance ValidValue Distance where validValue (Distance x) = nonnegative x
instance ValidValue Altitude where validValue (Altitude x) = finite x
instance ValidValue Duration where validValue (Duration x) = nonnegative x
instance ValidValue Energy where validValue (Energy x) = nonnegative x
instance ValidValue Temperature where validValue (Temperature x) = finite x && x >= -273.15
instance ValidValue Percentage where validValue (Percentage x) = bounded 0 100 x
instance ValidValue Grade where validValue (Grade x) = finite x
instance ValidValue Bearing where validValue (Bearing x) = nonnegative x && x < 360
instance ValidValue Mass where validValue (Mass x) = positive x
instance ValidValue IntensityFactor where validValue (IntensityFactor x) = nonnegative x
instance ValidValue TrainingStress where validValue (TrainingStress x) = nonnegative x
instance ValidValue Position where
    validValue p = bounded (-90) 90 (latitude p) && bounded (-180) 180 (longitude p)
instance ValidValue Double where validValue = finite

optional :: (ValidValue a) => Text -> Maybe a -> [ValidationError]
optional field = maybe [] (check field "Invalid or non-finite measurement" . validValue)

rangeErrors :: Text -> TimeRange -> [ValidationError]
rangeErrors field r = check field "Start must precede end" (rangeStart r < rangeEnd r)

inside :: TimeRange -> Data.Time.UTCTime -> Bool
inside r t = rangeStart r <= t && t <= rangeEnd r

adjacent :: (a -> a -> Bool) -> V.Vector a -> Bool
adjacent relation xs = V.and (V.zipWith relation xs (V.drop 1 xs))

-- Reject malformed input rather than sort, interpolate or silently drop it.
-- Indexes in errors refer to the original input.
validateTimeSeries :: (a -> Bool) -> TimeRange -> TimeSeries a -> [ValidationError]
validateTimeSeries valid r xs =
    rangeErrors "range" r
        ++ check
            "timestamps"
            "Measurement timestamps must be strictly increasing"
            (adjacent (\a b -> timestamp a < timestamp b) xs)
        ++ concat (V.toList (V.imap point xs))
  where
    point i sample =
        let field = T.pack (show i)
         in check field "Timestamp outside workout" (inside r (timestamp sample))
                ++ check field "Invalid or non-finite measurement" (valid (value sample))

prefix :: Text -> [ValidationError] -> [ValidationError]
prefix field errors = qualify <$> errors
  where
    qualify err = err {errorField = field <> "." <> errorField err}

series :: (ValidValue a) => Text -> TimeRange -> TimeSeries a -> [ValidationError]
series field r = prefix field . validateTimeSeries validValue r

cumulative :: (ValidValue a, Ord a) => Text -> TimeRange -> TimeSeries a -> [ValidationError]
cumulative field r xs =
    series field r xs
        ++ check
            field
            "Cumulative values must not decrease"
            (adjacent (\a b -> value a <= value b) xs)

statistics :: (ValidValue a, Ord a) => Text -> Statistics a -> [ValidationError]
statistics field s =
    optional (field <> ".min") (minimumValue s)
        ++ optional (field <> ".average") (averageValue s)
        ++ optional (field <> ".max") (maximumValue s)
        ++ check
            field
            "Statistics must satisfy min <= average <= max"
            (and (zipWith (<=) values (drop 1 values)))
  where
    values = catMaybes [minimumValue s, averageValue s, maximumValue s]

summaries :: (a -> [ValidationError]) -> Summaries a -> [ValidationError]
summaries validate s =
    prefix "recorded" (validate (recordedSummary s))
        ++ maybe [] calculated (calculatedSummary s)
  where
    calculated c =
        check
            "calculated.method"
            "Calculation method/version is required"
            (not (T.null (T.strip (calculationMethod c))))
            ++ prefix "calculated" (validate (calculationValue c))

-- Simultaneous events are legitimate. Stable input order is preserved.
events :: Text -> TimeRange -> (a -> [ValidationError]) -> V.Vector (Timed a) -> [ValidationError]
events field r validate xs =
    check
        field
        "Events must be ordered by time"
        (adjacent (\a b -> timestamp a <= timestamp b) xs)
        ++ concat (V.toList (V.imap event xs))
  where
    event i x =
        prefix
            (field <> "." <> T.pack (show i))
            (check "time" "Timestamp outside workout" (inside r (timestamp x)) ++ validate (value x))

extensions :: TimeRange -> V.Vector ExtensionField -> [ValidationError]
extensions r xs =
    check
        "extensions"
        "Extension keys must be unique"
        (length keys == length (nub keys))
        ++ concatMap field (V.toList xs)
  where
    keys = extensionKey <$> V.toList xs
    field e =
        prefix ("extensions." <> extensionKey e) $
            check "key" "Extension key is required" (not (T.null (T.strip (extensionKey e))))
                ++ case extensionData e of
                    NumericExtension _ samples stats -> series "samples" r samples ++ statistics "summary" stats
                    TextExtension samples _ -> prefix "samples" (validateTimeSeries (const True) r samples)
                    BooleanExtension samples _ -> prefix "samples" (validateTimeSeries (const True) r samples)

laps :: (a -> [ValidationError]) -> TimeRange -> V.Vector (Lap a) -> [ValidationError]
laps validate r xs =
    check
        "laps"
        "Laps must be ordered and non-overlapping"
        (adjacent (\a b -> rangeEnd (lapRange a) <= rangeStart (lapRange b)) xs)
        ++ concat (V.toList (V.imap one xs))
  where
    one i l =
        prefix ("laps." <> T.pack (show i)) $
            rangeErrors "range" (lapRange l)
                ++ check
                    "range"
                    "Lap outside workout"
                    (inside r (rangeStart (lapRange l)) && inside r (rangeEnd (lapRange l)))
                ++ summaries validate (lapSummary l)
                ++ extensions (lapRange l) (lapExtensions l)

calculatedRevisionErrors :: WorkoutRevision -> Text -> Summaries a -> [ValidationError]
calculatedRevisionErrors revision field = maybe [] validateCalculated . calculatedSummary
  where
    validateCalculated calculated =
        prefix field $
            check
                "inputRevision"
                "Computed summary is stale"
                (calculationInputRevision calculated == revision)
                ++ check
                    "config"
                    "Calculation configuration is required"
                    (not (T.null (T.strip (calculationConfig calculated))))
