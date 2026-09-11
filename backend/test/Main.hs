module Main (main) where

import Control.Monad (forM_, unless)
import qualified ImportOutputTests
import qualified ImportStateTests
import qualified WorkoutTests

main :: IO ()
main = do
    let cases = WorkoutTests.cases ++ ImportStateTests.cases ++ ImportOutputTests.cases
    forM_ cases $ \(name, ok) -> unless ok (fail name)
    putStrLn ("Passed " ++ show (length cases) ++ " domain and import-state checks")
