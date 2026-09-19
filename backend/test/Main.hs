module Main (main) where

import qualified AnalysisTests
import Control.Monad (forM_, unless)
import qualified CyclingTests
import qualified FatigueTests
import qualified HeartRateTests
import qualified HistoryRequestTests
import qualified ImportOutputTests
import qualified ImportStateTests
import qualified PowerCurveTests
import qualified ProfileTests
import qualified RunningTests
import qualified StatisticsTests
import qualified WorkoutTests

main :: IO ()
main = do
    let cases =
            WorkoutTests.cases
                ++ CyclingTests.cases
                ++ RunningTests.cases
                ++ StatisticsTests.cases
                ++ PowerCurveTests.cases
                ++ AnalysisTests.cases
                ++ ProfileTests.cases
                ++ HeartRateTests.cases
                ++ FatigueTests.cases
                ++ HistoryRequestTests.cases
                ++ ImportStateTests.cases
                ++ ImportOutputTests.cases
    forM_ cases $ \(name, ok) -> unless ok (fail name)
    putStrLn ("Passed " ++ show (length cases) ++ " domain and import-state checks")
