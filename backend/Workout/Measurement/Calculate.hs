{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE FlexibleContexts #-}

module Workout.Measurement.Calculate (sampleStatistics) where

import Data.Coerce (Coercible, coerce)
import Data.Time (diffUTCTime)
import qualified Data.Vector as V
import Workout.Measurement.Types

-- Inputs are canonically validated, strictly ordered samples in canonical units.
-- Integrate linear segments only across gaps <= 120 seconds. Never extrapolate
-- to workout boundaries or interpret missing observations as zeros. A singleton
-- has extrema, but no time-supported mean. All real zeros participate.
sampleStatistics :: (Coercible a Double) => TimeSeries a -> Statistics a
sampleStatistics samples = Statistics (coerce <$> lo) (coerce <$> mean) (coerce <$> hi)
  where
    (_, lo, hi, _, mean) = V.foldl' step (Nothing, Nothing, Nothing, 0, Nothing) samples
    step (!previous, !low, !high, !covered, !average) sample =
        let x = coerce (value sample) :: Double
            !lowest = maybe x (min x) low
            !highest = maybe x (max x) high
            low' = Just lowest
            high' = Just highest
            (!covered', !average') = case previous of
                Just prior
                    | let dt = realToFrac (diffUTCTime (timestamp sample) (timestamp prior))
                    , dt > 0 && dt <= 120 ->
                        let before = coerce (value prior) :: Double
                            midpoint = before / 2 + x / 2
                            total = covered + dt
                            weighted =
                                maybe
                                    midpoint
                                    (\old -> old * (covered / total) + midpoint * (dt / total))
                                    average
                            -- Force the payload as well as Just to avoid retaining
                            -- a chain of unevaluated means for large FIT streams.
                            -- Clamp rounding noise within finite input bounds.
                            !bounded = min highest (max lowest weighted)
                         in (total, Just bounded)
                _ -> (covered, average)
         in (Just sample, low', high', covered', average')
