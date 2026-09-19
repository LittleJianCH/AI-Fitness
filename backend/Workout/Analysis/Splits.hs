module Workout.Analysis.Splits (splitSets, compareHalves) where

import Data.Maybe (mapMaybe)
import qualified Data.Vector as V
import Workout.Analysis.Series
import Workout.Analysis.Types

-- Distance splits require a continuous, nondecreasing cumulative distance
-- stream. Never derive distance from GPS or invent a start-to-first-sample leg.
splitSets :: Samples -> Samples -> Samples -> Samples -> Samples -> V.Vector SplitSet
splitSets distance hr watts cadence altitude =
    V.fromList
        [SplitSet lengthMetres (V.fromList (build lengthMetres)) | lengthMetres <- [1000, 5000]]
  where
    build width = case extent distance of
        Nothing -> []
        Just ((startTime, startDistance), (endTime, endDistance))
            | endDistance - startDistance > width * 2000 -> []
            | otherwise ->
                let targets =
                        [ startDistance + width * fromIntegral i
                        | i <- [1 .. ceiling ((endDistance - startDistance) / width) - 1 :: Int]
                        ]
                    boundaries = (startTime, startDistance) : mapMaybe (distanceTime distance) targets <> [(endTime, endDistance)]
                 in zipWith (makeSplit hr watts cadence altitude) [1 ..] (zip boundaries (drop 1 boundaries))

makeSplit
    :: Samples
    -> Samples
    -> Samples
    -> Samples
    -> Int
    -> ((Double, Double), (Double, Double))
    -> DistanceSplit
makeSplit hr watts cadence altitude index ((a, x), (b, y)) =
    DistanceSplit
        index
        a
        b
        (y - x)
        ((y - x) / (b - a))
        (avg hr)
        (avg watts)
        (avg cadence)
        elevation
  where
    avg = average . clip a b . segments 120 . window a b
    elevation = (-) <$> at 120 altitude b <*> at 120 altitude a

compareHalves :: Samples -> Maybe SplitComparison
compareHalves distance = do
    ((a, x), (b, y)) <- extent distance
    (middle, _) <- distanceTime distance (x / 2 + y / 2)
    first <- ratio ((y - x) / 2) (middle - a)
    second <- ratio ((y - x) / 2) (b - middle)
    percent <- (* 100) <$> ratio (second - first) first
    pure (SplitComparison first second percent)

extent :: Samples -> Maybe ((Double, Double), (Double, Double))
extent xs
    | V.length xs < 2 = Nothing
    | not (V.all valid (V.zip xs (V.drop 1 xs))) = Nothing
    | y <= x = Nothing
    | otherwise = Just (first, lastPoint)
  where
    first@(_, x) = V.head xs
    lastPoint@(_, y) = V.last xs
    valid ((a, p), (b, q)) = b > a && b - a <= 120 && q >= p

distanceTime :: Samples -> Double -> Maybe (Double, Double)
distanceTime xs target
    | i <= 0 || i >= V.length xs = Nothing
    | otherwise =
        let (a, x) = xs V.! (i - 1); (b, y) = xs V.! i
         in if y > x then Just (a + (b - a) * ((target - x) / (y - x)), target) else Nothing
  where
    i = lowerBound snd target xs

-- Include bracketing samples, then clip at the exact split boundary. Adjacent
-- splits visit only their own span instead of rescanning every sensor stream.
window :: Double -> Double -> Samples -> Samples
window lo hi xs = V.slice start (end - start) xs
  where
    start = max 0 (lowerBound fst lo xs - 1)
    end = min (V.length xs) (lowerBound fst hi xs + 1)

lowerBound :: ((Double, Double) -> Double) -> Double -> Samples -> Int
lowerBound field target xs = search 0 (V.length xs)
  where
    search lo hi | lo >= hi = lo
    search lo hi =
        let mid = (lo + hi) `div` 2
         in if field (xs V.! mid) < target then search (mid + 1) hi else search lo mid
