{-# LANGUAGE OverloadedStrings #-}

module Analysis.Fatigue.Calculate (analyseFatigue, defaultFatigueConfig) where

import Analysis.Fatigue.Daily (summarizeDays)
import Analysis.Fatigue.Types
import Analysis.HeartRate.Calculate (hrssMethod)
import Analysis.HeartRate.Types
import Control.Monad (unless)
import Data.Time (Day, UTCTime)

defaultFatigueConfig :: FatigueConfig
defaultFatigueConfig = FatigueConfig 42 7

-- Recompute from the same initial state after imports, exclusions, deletions or
-- profile corrections. Display-window cropping belongs AFTER this recurrence.
-- No database, wall clock, global settings, or implicit fallback load model.
analyseFatigue
    :: (UTCTime -> Day)
    -> CoveragePolicy
    -> HrssProfiles
    -> FatigueConfig
    -> InitialState
    -> [HistoryDay]
    -> Either FatigueError FatigueHistory
analyseFatigue localDay coverage profiles config initial days = do
    let ctlDays = fitnessTimeConstant config
        atlDays = fatigueTimeConstant config
    unless
        (all finite [ctlDays, atlDays] && atlDays >= 1 && atlDays < ctlDays && ctlDays <= 36525)
        (Left InvalidFatigueConfig)
    seed <- case initial of
        AssumeNoPriorLoad -> pure (0, 0)
        KnownPriorLoad ctl atl -> do
            unless (all (\x -> finite x && x >= 0) [ctl, atl]) (Left InvalidInitialState)
            pure (ctl, atl)
    loads <- summarizeDays localDay coverage profiles days
    let points = go 1 (Just seed) loads
    pure
        (FatigueHistory "fatigue.hrss-ewma.v1" hrssMethod config coverage profiles initial loads points)
  where
    finite x = not (isNaN x || isInfinite x)
    ctlDecay = exp (-(1 / fitnessTimeConstant config))
    atlDecay = exp (-(1 / fatigueTimeConstant config))
    go _ _ [] = []
    go count prior (day : rest) =
        let load = totalDailyLoad day
            next = do
                (ctl, atl) <- prior
                n <- load
                pure (ctl * ctlDecay + n * (1 - ctlDecay), atl * atlDecay + n * (1 - atlDecay))
            point =
                FatiguePoint
                    (loadDate day)
                    load
                    (fst <$> next)
                    (snd <$> next)
                    (uncurry (-) <$> next)
                    count
                    (ctlDecay ** fromIntegral count)
                    (atlDecay ** fromIntegral count)
         in point : go (count + 1) next rest
