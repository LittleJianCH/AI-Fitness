{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE FlexibleContexts #-}

module Workout.Analysis.Series
    ( Samples
    , Segment (..)
    , samples
    , segments
    , withinGap
    , clip
    , average
    , covered
    , integral
    , at
    , between
    , finite
    , ratio
    , mean
    , numericStatistics
    , excludingZeros
    , distribution
    , relationships
    , deriveSegments
    ) where

import Data.Coerce (Coercible, coerce)
import Data.Maybe (mapMaybe)
import Data.Time (UTCTime, diffUTCTime)
import qualified Data.Vector as V
import Workout.Analysis.Types
import Workout.Measurement.Types

type Samples = V.Vector (Double, Double)
data Segment = Segment {fromTime :: !Double, toTime :: !Double, fromValue :: !Double, toValue :: !Double}
    deriving (Eq, Show)

samples :: (Coercible a Double) => UTCTime -> TimeSeries a -> Samples
samples origin = V.map (\(Timed time x) -> (realToFrac (diffUTCTime time origin), coerce x))

segments :: Double -> Samples -> [Segment]
segments gap xs =
    [ Segment a b x y
    | ((a, x), (b, y)) <- V.toList (V.zip xs (V.drop 1 xs))
    , withinGap gap a b
    ]

-- Elapsed timestamps are converted from exact NominalDiffTime to Double.
-- Allow only the rounding uncertainty of those conversions/subtraction (four
-- machine epsilons at their magnitude, capped at one nanosecond), not a
-- fixed gap-filling allowance.
withinGap :: Double -> Double -> Double -> Bool
withinGap gap a b =
    b > a && not (isInfinite delta) && (delta <= gap || delta - gap <= tolerance)
  where
    delta = b - a
    tolerance = min 1e-9 (4 * encodeFloat 1 (-52) * maximum [1, abs a, abs b, abs gap])

clip :: Double -> Double -> [Segment] -> [Segment]
clip lo hi = mapMaybe cut
  where
    cut s@(Segment a b _ _) =
        let from = max lo a; to = min hi b
         in if to > from then Just (Segment from to (valueAt from s) (valueAt to s)) else Nothing

valueAt :: Double -> Segment -> Double
valueAt t (Segment a b x y) = let f = (t - a) / (b - a) in x * (1 - f) + y * f

covered :: [Segment] -> Double
covered = foldl' (\total s -> total + toTime s - fromTime s) 0

average :: [Segment] -> Maybe Double
average = snd . foldl' step (0, Nothing)
  where
    step (!duration, !old) (Segment a b x y) =
        let dt = b - a
            total = duration + dt
            midpoint = x / 2 + y / 2
            !result = maybe midpoint (\v -> v * (duration / total) + midpoint * (dt / total)) old
         in (total, finite result)

integral :: [Segment] -> Maybe Double
integral xs = average xs >>= finite . (* covered xs)

-- Binary lookup retains independent sensor clocks; no extrapolation or gap fill.
at :: Double -> Samples -> Double -> Maybe Double
at gap xs t
    | V.null xs = Nothing
    | otherwise = lookupIndex (search 0 (V.length xs))
  where
    search lo hi | lo >= hi = lo
    search lo hi =
        let mid = (lo + hi) `div` 2
         in if fst (xs V.! mid) < t then search (mid + 1) hi else search lo mid
    lookupIndex i
        | i < V.length xs, (u, y) <- xs V.! i, u == t = Just y
        | i > 0
        , i < V.length xs
        , (a, x) <- xs V.! (i - 1)
        , (b, y) <- xs V.! i
        , withinGap gap a b =
            finite (valueAt t (Segment a b x y))
        | otherwise = Nothing

between :: Double -> Double -> Samples -> Samples
between lo hi = V.filter (\(t, _) -> t >= lo && t <= hi)

finite :: Double -> Maybe Double
finite x
    | isNaN x || isInfinite x = Nothing
    | otherwise = Just x

ratio :: Double -> Double -> Maybe Double
ratio x y
    | y > 0 = finite (x / y)
    | otherwise = Nothing

mean :: [Double] -> Maybe Double
mean [] = Nothing
mean xs = let count = fromIntegral (length xs) in finite (foldl' (\acc x -> acc + x / count) 0 xs)

numericStatistics :: Samples -> Statistics Double
numericStatistics xs = Statistics lo (average (segments 120 xs)) hi
  where
    values = V.map snd xs
    lo = if V.null values then Nothing else Just (V.minimum values)
    hi = if V.null values then Nothing else Just (V.maximum values)

-- Positive-duration zero plateaus are removed; isolated zero endpoints have
-- measure zero and do not delete adjacent positive ramps.
excludingZeros :: [Segment] -> Maybe Double
excludingZeros = average . filter (\s -> fromValue s /= 0 || toValue s /= 0)

-- Derive at every breakpoint of both clocks. Intersect supported segments
-- directly so missing/invalid intervals cannot be bridged by surviving points.
deriveSegments :: (Double -> Double -> Maybe Double) -> Samples -> Samples -> [Segment]
deriveSegments derive xs ys = align (segments 120 xs) (segments 120 ys)
  where
    align [] _ = []
    align _ [] = []
    align left@(x : restX) right@(y : restY) =
        let lo = max (fromTime x) (fromTime y)
            hi = min (toTime x) (toTime y)
            result = do
                a <- derive (valueAt lo x) (valueAt lo y) >>= finite
                b <- derive (valueAt hi x) (valueAt hi y) >>= finite
                pure (Segment lo hi a b)
            next = case compare (toTime x) (toTime y) of
                LT -> align restX right
                EQ -> align restX restY
                GT -> align left restY
         in if hi <= lo then next else maybe next (: next) result

distribution :: Double -> Samples -> V.Vector DistributionBin
distribution base xs
    | V.null xs = V.empty
    | Nothing <- finite (hi - lo) = V.empty
    | Nothing <- finite (hi + width) = V.empty
    | otherwise =
        V.fromList
            [ DistributionBin lower upper (sum (map (durationInside lower upper) spans))
            | i <- [0 .. count - 1]
            , let lower = lo + fromIntegral i * width
            , let upper = lo + fromIntegral (i + 1) * width
            ]
  where
    lo = V.minimum (V.map snd xs)
    hi = V.maximum (V.map snd xs)
    width = maximum [base, (hi - lo) / 63, max (abs lo) (abs hi) * 1e-12]
    count = min 64 (1 + floor ((hi - lo) / width)) :: Int
    spans = segments 120 xs
    durationInside lower upper (Segment a b x y)
        | x == y = if x >= lower && x < upper then b - a else 0
        | otherwise = (b - a) * (max 0 (min upper (max x y) - max lower (min x y)) / abs (y - x))

relationships :: MetricKind -> MetricKind -> Samples -> Samples -> MetricRelationship
relationships xKind yKind xs ys = MetricRelationship xKind yKind (length pairs) correlation shown
  where
    pairs = mapMaybe (\(t, x) -> RelationshipPoint x <$> at 120 ys t) (V.toList xs)
    points = V.fromList pairs
    count = V.length points
    shown
        | count <= 600 = points
        | otherwise = V.generate 600 (\i -> points V.! (i * (count - 1) `div` 599))
    correlation = do
        let sx = foldl' (\m p -> max m (abs (relationshipXValue p))) 0 pairs
            sy = foldl' (\m p -> max m (abs (relationshipYValue p))) 0 pairs
            constant field = case pairs of [] -> True; p : ps -> all ((== field p) . field) ps
        if length pairs < 2 || sx == 0 || sy == 0 || constant relationshipXValue || constant relationshipYValue
            then Nothing
            else do
                mx <- mean (map ((/ sx) . relationshipXValue) pairs)
                my <- mean (map ((/ sy) . relationshipYValue) pairs)
                let centered = [(relationshipXValue p / sx - mx, relationshipYValue p / sy - my) | p <- pairs]
                    xx = sum [x * x | (x, _) <- centered]
                    yy = sum [y * y | (_, y) <- centered]
                    xy = sum [x * y | (x, y) <- centered]
                max (-1) . min 1 <$> ratio xy (sqrt xx * sqrt yy)
