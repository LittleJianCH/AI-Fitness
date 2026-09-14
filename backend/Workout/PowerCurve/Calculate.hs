{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

module Workout.PowerCurve.Calculate (calculate, curvePoints) where

import Data.Time (addUTCTime, diffUTCTime)
import qualified Data.Vector as V
import Workout.Measurement.Types
import Workout.PowerCurve.Types
import qualified Workout.Sport as Sport
import Workout.Types (Workout (..), WorkoutObservation (..))

calculate :: Workout -> PowerCurve
calculate workout =
    PowerCurve
        (workoutId workout)
        (workoutRevision workout)
        "linear-best-duration-v1"
        gapSeconds
        (curvePoints (Sport.power (observationSport (workoutObservation workout))))

gapSeconds :: Int
gapSeconds = 5

-- Canonically validated, strictly ordered samples in watts. Time is elapsed
-- time; timer events do not remove intervals or invent sensor observations.
curvePoints :: TimeSeries Power -> V.Vector PowerCurvePoint
curvePoints samples = V.fromList [PowerCurvePoint d (bestFor d) | d <- durations]
  where
    durations = [1, 5, 10, 15, 30] <> map (* 60) minutes
    minutes = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]
    runs = splitRuns (V.toList samples)
    prepared = map prepare runs
    bestFor d = foldl' choose Nothing [effort | run <- prepared, let effort = scan d run]

splitRuns :: [Timed Power] -> [[Timed Power]]
splitRuns [] = []
splitRuns (first : rest) = go first [first] rest
  where
    go _ acc [] = [reverse acc]
    go prior acc (next : remaining)
        | diffUTCTime (timestamp next) (timestamp prior) <= fromIntegral gapSeconds =
            go next (next : acc) remaining
        | otherwise = reverse acc : go next [next] remaining

-- Each knot stores elapsed time, normalized power and its cumulative integral.
-- Scaling before integration keeps even large finite canonical powers finite.
type Knot = (Double, Double, Double)
type Run = (Maybe (Timed Power), Double, [Knot])

prepare :: [Timed Power] -> Run
prepare [] = (Nothing, 0, [])
prepare samples@(first : _) = (Just first, scale, build 0 coordinates)
  where
    watts (Timed _ (Power p)) = p
    scale = foldl' (\acc sample -> max acc (watts sample)) 0 samples
    coordinates =
        [ ( realToFrac (diffUTCTime (timestamp sample) (timestamp first))
          , if scale == 0 then 0 else watts sample / scale
          )
        | sample <- samples
        ]
    build _ [] = []
    build !area [(t, p)] = [(t, p, area)]
    build !area ((t, p) : next@(u, q) : rest) =
        (t, p, area) : build (area + (u - t) * (p / 2 + q / 2)) (next : rest)

scan :: Int -> Run -> Maybe PowerEffort
scan duration (Just first, scale, knots@((begin, _, _) : _)) = do
    (finish, _, _) <- lastKnot knots
    let width = fromIntegral duration
        limit = finish - width
        -- Both cursors only advance. At their merged breakpoints the window
        -- integral is quadratic; its derivative is P(t + width) - P(t).
        go !t left right !winner
            | t > limit = winner
            | otherwise =
                let l = advance t left
                    r = advance (t + width) right
                    candidate x = do
                        (_, a) <- at x l
                        (_, b) <- at (x + width) r
                        let mean = min 1 (max 0 ((b - a) / width)) * scale
                            from = addUTCTime (realToFrac x) (timestamp first)
                            windowEnd = addUTCTime (fromIntegral duration) from
                        pure (PowerEffort (Power mean) from windowEnd)
                    winner' = choose winner (candidate t)
                    next = minimum (limit : nextTime l <> map (subtract width) (nextTime r))
                    derivative x = do
                        (rightPower, _) <- at (x + width) r
                        (leftPower, _) <- at x l
                        pure (rightPower - leftPower)
                    stationary = do
                        before <- derivative t
                        after <- derivative next
                        if before > 0 && after < 0
                            then candidate (t + (next - t) * (before / (before - after)))
                            else Nothing
                 in if next <= t
                        then winner'
                        else go next l r (choose winner' stationary)
    if limit < begin then Nothing else go begin knots knots Nothing
scan _ _ = Nothing

lastKnot :: [Knot] -> Maybe Knot
lastKnot = foldl' (\_ knot -> Just knot) Nothing

advance :: Double -> [Knot] -> [Knot]
advance t (_ : next@(u, _, _) : rest) | u <= t = advance t (next : rest)
advance _ knots = knots

nextTime :: [Knot] -> [Double]
nextTime (_ : (t, _, _) : _) = [t]
nextTime _ = []

at :: Double -> [Knot] -> Maybe (Double, Double)
at t ((a, p, area) : (b, q, _) : _) =
    let fraction = min 1 (max 0 ((t - a) / (b - a)))
        valueAt = p * (1 - fraction) + q * fraction
     in Just (valueAt, area + (t - a) * (p / 2 + valueAt / 2))
at _ [(_, p, area)] = Just (p, area)
at _ [] = Nothing

choose :: Maybe PowerEffort -> Maybe PowerEffort -> Maybe PowerEffort
choose Nothing candidate = candidate
choose winner Nothing = winner
choose winner@(Just old) candidate@(Just new)
    | newPower - oldPower > tolerance = candidate
    | abs (newPower - oldPower) <= tolerance && start new < start old = candidate
    | otherwise = winner
  where
    Power oldPower = averagePower old
    Power newPower = averagePower new
    -- Prefix-integral subtraction can perturb equal plateaus. Resolve values
    -- equal within relative floating-point tolerance by their earliest start.
    tolerance = 1e-12 * max oldPower newPower
