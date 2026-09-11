module Main (main) where

import Control.Monad (forM_, replicateM_, unless, (>=>))
import Data.Bits (xor)
import qualified Data.ByteString as BS
import Data.Maybe (isNothing)
import Data.Time (UTCTime (..), addUTCTime, fromGregorian)
import qualified Data.Vector as V
import Import.Fit
import System.Environment (getArgs)
import Workout.Common.Types
import Workout.Types

assert :: String -> Bool -> IO ()
assert name passed = unless passed (fail name)

main :: IO ()
main = do
    args <- getArgs
    case args of
        [directory] -> syntheticTests directory
        ["--private-cycling", path] -> do
            result <- readFit path
            case result of
                Right observation -> case observationSport observation of
                    Cycling _ -> putStrLn "Private cycling sample: passed"
                    _ -> fail "Private cycling sample: wrong sport"
                Left err -> fail ("Private cycling sample: " ++ errorCategory err)
        ["--private-running", path] -> do
            result <- readFit path
            case result of
                Right observation -> case observationSport observation of
                    Running _ -> putStrLn "Private running sample: passed"
                    _ -> fail "Private running sample: wrong sport"
                Left err -> fail ("Private running sample: " ++ errorCategory err)
        _ -> fail "Provide synthetic fixture directory or a private sample mode and path"

-- Do not print observations, filenames, timestamps or field values for private inputs.
errorCategory :: FitError -> String
errorCategory err = case err of
    InvalidFit -> "invalid binary"
    UnsupportedFit -> "unsupported activity"
    MissingFitTime -> "missing absolute timestamp"
    FitResourceLimit -> "resource limit"
    FitAdapterFailure -> "adapter failure"
    FitFileUnreadable -> "unreadable file"
    InvalidFitObservation _ -> "domain validation failure"

syntheticTests :: FilePath -> IO ()
syntheticTests directory = do
    let readFixture name = readFit (directory ++ "/" ++ name ++ ".fit")
    result <- readFixture "cycling"
    case result of
        Right observation -> case observationSport observation of
            Cycling ride -> do
                let motion = cyclingMotion ride
                    summary = cyclingCommonSummary (recordedSummary (cyclingSummary ride))
                    start = addUTCTime 1100000000 (UTCTime (fromGregorian 1989 12 31) 0)
                assert
                    "FIT UTC epoch and session range"
                    (observationRange observation == TimeRange start (addUTCTime 30 start))
                assert
                    "Missing and invalid heart rate stay absent"
                    ((value <$> motionHeartRate motion) == V.fromList [HeartRate 120, HeartRate 130])
                assert
                    "Zero power is retained, invalid power omitted"
                    ((value <$> motionPower motion) == V.fromList [Power 0, Power 210])
                assert
                    "Scaled and enhanced speed"
                    ((value <$> motionSpeed motion) == V.fromList [Speed 5.25, Speed 6.25])
                assert
                    "Distance uses metres"
                    ((value <$> motionDistance motion) == V.fromList [Distance 0, Distance 52.5, Distance 115])
                assert
                    "Elapsed and timer durations remain distinct"
                    (summaryElapsedTime summary == Just (Duration 30) && summaryTimerTime summary == Just (Duration 20))
                assert "Device total distance retained" (summaryDistance summary == Just (Distance 115))
                assert
                    "No invented moving time or computed summary"
                    (isNothing (summaryMovingTime summary) && isNothing (calculatedSummary (cyclingSummary ride)))
            _ -> fail "Expected cycling"
        Left err -> fail (show err)
    running <- readFixture "running"
    case (result, running) of
        (Right rideObservation, Right runObservation) -> case (observationSport rideObservation, observationSport runObservation) of
            (Cycling ride, Running run) -> do
                assert "Both sports share motion mapping" (cyclingMotion ride == runningMotion run)
                assert
                    "Running cadence counts both feet including fractions"
                    ((value <$> runningCadence run) == V.fromList [RunningCadence 161, RunningCadence 180.5])
                assert
                    "Cycling cadence stays cycles per minute"
                    ((value <$> cyclingCadence ride) == V.fromList [CyclingCadence 80.5, CyclingCadence 90.25])
                assert
                    "Negative altitude and enhanced altitude preserved"
                    ((value <$> motionAltitude (runningMotion run)) == V.fromList [Altitude (-10), Altitude 120])
                assert
                    "GPS converts semicircles and omits incomplete pairs"
                    ((value <$> motionPosition (runningMotion run)) == V.singleton (Position 45 (-90)))
                assert
                    "Running reported totals retained without computed values"
                    ( runningCommonSummary (recordedSummary (runningSummary run))
                        == cyclingCommonSummary (recordedSummary (cyclingSummary ride))
                        && isNothing (calculatedSummary (runningSummary run))
                    )
            _ -> fail "Sport dispatch mismatch"
        _ -> fail "Both sport fixtures must decode"
    forM_
        [ ("swimming", UnsupportedFit)
        , ("course", UnsupportedFit)
        , ("multisport", UnsupportedFit)
        , ("no-session", UnsupportedFit)
        , ("missing-record-time", MissingFitTime)
        , ("missing-session-time", MissingFitTime)
        , ("relative-time", MissingFitTime)
        , ("limit", FitResourceLimit)
        ]
        $ \(name, expected) ->
            readFixture name >>= assert name . (== Left expected)
    forM_ ["duplicate-time", "outside-range", "running-duplicate-time", "running-invalid-position"] $ \name -> do
        bad <- readFixture name
        assert name (case bad of Left (InvalidFitObservation (_ : _)) -> True; _ -> False)
    absent <- readFixture "missing-summary"
    assert
        "Missing totals are not invented"
        ( case absent of
            Right observation -> case observationSport observation of
                Cycling ride ->
                    let summary = cyclingCommonSummary (recordedSummary (cyclingSummary ride))
                     in isNothing (summaryElapsedTime summary)
                            && isNothing (summaryTimerTime summary)
                            && isNothing (summaryDistance summary)
                _ -> False
            _ -> False
        )
    bytes <- BS.readFile (directory ++ "/cycling.fit")
    forM_
        [ BS.empty
        , BS.take 8 bytes
        , BS.take (BS.length bytes - 1) bytes
        , bytes <> bytes
        , BS.map (`xor` 1) bytes
        , BS.init bytes <> BS.singleton (BS.last bytes `xor` 1)
        ]
        (parseFit >=> assert "Malformed/truncated/CRC/trailing data rejected" . (== Left InvalidFit))
    parseFit (BS.replicate (16 * 1024 * 1024 + 1) 0)
        >>= assert "Input byte limit" . (== Left FitResourceLimit)
    readFit (directory ++ "/not-present.fit")
        >>= assert "File IO failure" . (== Left FitFileUnreadable)
    replicateM_ 100 (parseFit bytes >>= assert "Repeated allocation and release" . (== result))
    putStrLn "Passed FIT decoding, normalization, rejection and resource checks"
