module Import.Fit (readFit, parseFit, FitError (..)) where

import Control.Exception (IOException, catch)
import qualified Data.ByteString as BS
import Import.Fit.Decode (decodeFit, maxFitBytes)
import Import.Fit.Normalize (normalizeWorkout)
import Import.Fit.Types (FitError (..))
import System.IO (IOMode (ReadMode), withBinaryFile)
import Workout.Types (WorkoutObservation)

parseFit :: BS.ByteString -> IO (Either FitError WorkoutObservation)
parseFit bytes = (>>= normalizeWorkout) <$> decodeFit bytes

-- Read at most the limit plus one byte to detect oversized input before decoding.
-- Only filesystem exceptions are translated; asynchronous cancellation propagates.
readFit :: FilePath -> IO (Either FitError WorkoutObservation)
readFit path =
    catch
        (withBinaryFile path ReadMode (\handle -> BS.hGet handle (maxFitBytes + 1)) >>= parseFit)
        unreadable
  where
    unreadable :: IOException -> IO (Either FitError WorkoutObservation)
    unreadable _ = pure (Left FitFileUnreadable)
