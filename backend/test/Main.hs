module Main (main) where

import Control.Monad (forM_, unless)
import qualified CyclingTests
import qualified ImportOutputTests
import qualified ImportStateTests
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
                ++ ImportStateTests.cases
                ++ ImportOutputTests.cases
    forM_ cases $ \(name, ok) -> unless ok (fail name)
    putStrLn ("Passed " ++ show (length cases) ++ " domain and import-state checks")
