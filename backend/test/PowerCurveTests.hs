module PowerCurveTests (cases) where

import Data.Maybe (isNothing)
import Data.Time (addUTCTime, diffUTCTime)
import qualified Data.Vector as V
import qualified Fixtures as F
import Workout.Measurement.Types
import Workout.PowerCurve.Calculate (curvePoints)
import Workout.PowerCurve.Types

cases :: [(String, Bool)]
cases =
    [
        ( "power curve: irregular plateau keeps earliest tied window"
        , matches
            5
            ( [(0, 400), (0.1, 0), (1, 200), (1.1, 200)]
                <> [(2.3, 200), (6.1, 200), (10.3, 200), (14.6, 200)]
            )
            200
            1
        )
    ,
        ( "power curve: empty and singleton have no duration support"
        , allMissing [] && allMissing [(0, 100)]
        )
    , ("power curve: real zeros produce zero efforts", matches 5 [(0, 0), (5, 0)] 0 0)
    ,
        ( "power curve: exact coverage and earliest tied effort"
        , matches 5 [(0, 200), (5, 200), (10, 200)] 200 0
        )
    ,
        ( "power curve: irregular samples are time weighted"
        , matches 5 [(0, 0), (1, 100), (5, 100)] 90 0
        )
    , ("power curve: five-second gap is included", matches 5 [(0, 0), (5, 100)] 50 0)
    ,
        ( "power curve: gap beyond five seconds breaks coverage"
        , allMissing [(0, 100), (5.000001, 100)]
        )
    ,
        ( "power curve: windows cannot cross disconnected runs"
        , isNothing (effort 10 [(0, 100), (5, 100), (11, 100), (16, 100)])
        )
    ,
        ( "power curve: later run can win"
        , matches 5 [(0, 100), (5, 100), (11, 200), (16, 200)] 200 11
        )
    ,
        ( "power curve: duration longer than coverage unavailable"
        , isNothing (effort 5 [(0, 100), (4.999, 100)])
        )
    ,
        ( "power curve: fractional endpoints are preserved"
        , matches 1 [(0.25, 100), (1.25, 100)] 100 0.25
        )
    ,
        ( "power curve: optimum can lie between sample timestamps"
        , matches 1 [(0, 0), (1, 100), (2, 0)] 75 0.5
        )
    , ("power curve: decreasing ramp selects left boundary", matches 1 [(0, 100), (5, 0)] 90 0)
    ,
        ( "power curve: nonterminating stationary offset is preserved"
        , matches 1 [(0, 50), (1, 100), (2, 0)] (250 / 3) (1 / 3)
        )
    , ("power curve: increasing ramp selects right boundary", matches 1 [(0, 0), (5, 100)] 90 4)
    ,
        ( "power curve: finite large power never overflows"
        , matches 5 [(0, 1.7e308), (5, 1.7e308)] 1.7e308 0
        )
    , ("power curve: finite large ramp never overflows", matches 5 [(0, 0), (5, 1.7e308)] 8.5e307 0)
    ,
        ( "power curve: long stream supports all durations"
        , all
            (maybe False ((== Power 200) . averagePower) . best)
            (V.toList (curvePoints (samples [(t, 200) | t <- [0 .. 30000]])))
        )
    ]

samples :: [(Double, Double)] -> TimeSeries Power
samples = V.fromList . map (\(t, p) -> Timed (addUTCTime (realToFrac t) F.start) (Power p))

effort :: Int -> [(Double, Double)] -> Maybe PowerEffort
effort seconds input =
    best =<< V.find ((== seconds) . durationSeconds) (curvePoints (samples input))

allMissing :: [(Double, Double)] -> Bool
allMissing = V.all (isNothing . best) . curvePoints . samples

matches :: Int -> [(Double, Double)] -> Double -> Double -> Bool
matches seconds input expected from = case effort seconds input of
    Nothing -> False
    Just result ->
        let Power actual = averagePower result
         in abs (actual / max 1 expected - expected / max 1 expected) < 1e-10
                && abs (realToFrac (diffUTCTime (start result) F.start) - from) < (1e-9 :: Double)
                && diffUTCTime (end result) (start result) == fromIntegral seconds
