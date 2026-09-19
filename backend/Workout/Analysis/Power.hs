{-# LANGUAGE BangPatterns #-}

module Workout.Analysis.Power (analysePower, normalizedPower) where

import qualified Data.Vector as V
import Workout.Analysis.Series
import Workout.Analysis.Types
import Workout.Measurement.Types
import Workout.Types (AthleteContext (..))

-- One-second integrals of the linearly interpolated signal, then complete
-- 30-second rolling means. Gaps >5 seconds reset the rolling window. Scale
-- before fourth powers to keep any finite canonical power representable.
normalizedPower :: Samples -> (Maybe Double, Double)
normalizedPower xs
    | V.null xs || totalDuration > 604800 = (Nothing, 0)
    | otherwise = (result, fromIntegral count)
  where
    spans = segments 5 xs
    totalDuration = covered spans
    runs = reverse (foldl' collect [] spans)
    collect [] s = [[s]]
    collect (run@(prior : _) : rest) s
        | toTime prior == fromTime s = (s : run) : rest
    collect rest s = [s] : rest
    windows = concatMap (rolling . reverse) runs
    (!count, !scale, !fourthMean) = foldl' accumulate (0 :: Int, 0, 0) windows
    -- Scale the fourth moment by contributing rolling windows, not isolated
    -- observations or runs too short to supply a window.
    accumulate (!n, !oldScale, !m) p =
        let next = n + 1
            newScale = max oldScale p
            oldRatio = if newScale == 0 then 0 else oldScale / newScale
            newRatio = if newScale == 0 then 0 else p / newScale
            !new = m * oldRatio ** 4 * (fromIntegral n / fromIntegral next) + newRatio ** 4 / fromIntegral next
         in (next, newScale, new)
    result
        | count == 0 = Nothing
        | scale == 0 = Just 0
        | otherwise = finite (fourthMean ** 0.25 * scale)
    rolling [] = []
    rolling original@(first : _) =
        let origin = fromTime first
            end = foldl' (\_ s -> toTime s) origin original
            duration = end - origin
            whole = floor duration :: Int
            -- Subtracting converted timestamps can put an exact whole-second
            -- duration just below its endpoint (e.g. 32.3 - 2.3). Admit only
            -- conversion-scale rounding, never a genuinely incomplete second.
            tolerance = min 1e-9 (4 * encodeFloat 1 (-52) * maximum [1, abs origin, abs end])
            n = if fromIntegral (whole + 1) - duration <= tolerance then whole + 1 else whole
            -- A fractional tail beyond the final one-second endpoint does not
            -- contribute to any complete window and must not change scaling.
            ss = clip origin (origin + fromIntegral n) original
            runScale = foldl' (\m s -> max m (max (fromValue s) (toValue s))) 0 ss
            divided x = if runScale == 0 then 0 else x / runScale
            knots = V.fromList (scanl add (origin, divided (fromValue first), 0) ss)
            add (_, _, area) s =
                ( toTime s
                , divided (toValue s)
                , area + (toTime s - fromTime s) * (divided (fromValue s) / 2 + divided (toValue s) / 2)
                )
            areaAt t =
                let search lo hi | lo >= hi = lo
                    search lo hi =
                        let mid = (lo + hi) `div` 2; (u, _, _) = knots V.! mid
                         in if u < t then search (mid + 1) hi else search lo mid
                    i = search 0 (V.length knots - 1)
                    (b, y, area) = knots V.! i
                 in if b == t || i == 0
                        then area
                        else
                            let (a, x, prior) = knots V.! (i - 1); f = (t - a) / (b - a)
                             in prior + (t - a) * (x / 2 + (x * (1 - f) + y * f) / 2)
         in [ runScale
                * max 0 (min 1 ((areaAt (origin + fromIntegral k) - areaAt (origin + fromIntegral (k - 30))) / 30))
            | k <- [30 .. n]
            ]

analysePower :: Double -> AthleteContext -> Samples -> Samples -> PowerAnalysis
analysePower elapsed athlete watts heart =
    PowerAnalysis
        np
        npSeconds
        variability
        intensity
        stress
        perKg
        work
        efficiency
        decoupling
        ftp
        mass
  where
    ps = segments 5 watts
    hs = segments 5 heart
    meanPower = average ps
    (np, npSeconds) = normalizedPower watts
    variability = (,) <$> np <*> meanPower >>= uncurry ratio
    ftp = case thresholdPower athlete of Just (Power p) -> Just p; Nothing -> Nothing
    mass = case athleteMass athlete of Just (Mass m) -> Just m; Nothing -> Nothing
    intensity = (,) <$> np <*> ftp >>= uncurry ratio
    perKg = (,) <$> meanPower <*> mass >>= uncurry ratio
    work = integral ps
    complete spans = elapsed > 0 && abs (covered spans - elapsed) <= 1e-6 * max 1 elapsed
    stress = if complete ps then intensity >>= finite . (\x -> x * x * elapsed / 36) else Nothing
    efficiency = if complete ps && complete hs then (,) <$> np <*> average hs >>= uncurry ratio else Nothing
    half = elapsed / 2
    halfEfficiency lo hi = do
        let p = clip lo hi ps; h = clip lo hi hs
        if hi - lo < 30 || abs (covered p - (hi - lo)) > 1e-6 || abs (covered h - (hi - lo)) > 1e-6
            then Nothing
            else do
                let boundary = maybe [] (\x -> [(lo, x)]) (at 5 watts lo)
                    ending = maybe [] (\x -> [(hi, x)]) (at 5 watts hi)
                    inner = V.filter (\(t, _) -> t > lo && t < hi) watts
                    (normalized, _) = normalizedPower (V.fromList boundary <> inner <> V.fromList ending)
                (,) <$> normalized <*> average h >>= uncurry ratio
    decoupling = do
        before <- halfEfficiency 0 half
        after <- halfEfficiency half elapsed
        change <- ratio (before - after) before
        finite (100 * change)
