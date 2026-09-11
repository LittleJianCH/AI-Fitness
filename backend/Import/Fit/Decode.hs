{-# LANGUAGE ForeignFunctionInterface #-}

module Import.Fit.Decode (decodeFit, maxFitBytes) where

import Control.Exception (bracket)
import qualified Data.ByteString as BS
import qualified Data.Vector as V
import Foreign (Ptr, alloca, castPtr, nullPtr, peek, peekArray, poke)
import Foreign.C.Types (CDouble (..), CInt (..), CSize (..))
import Import.Fit.Types

-- Opaque native allocation. Never expose it outside this module.
data NativeFit

foreign import ccall safe "af_fit_decode"
    cDecode :: Ptr a -> CSize -> Ptr (Ptr NativeFit) -> IO CInt
foreign import ccall unsafe "af_fit_free"
    cFree :: Ptr NativeFit -> IO ()
foreign import ccall unsafe "af_fit_summary"
    cSummary :: Ptr NativeFit -> IO (Ptr CDouble)
foreign import ccall unsafe "af_fit_record_count"
    cCount :: Ptr NativeFit -> IO CSize
foreign import ccall unsafe "af_fit_records"
    cRecords :: Ptr NativeFit -> IO (Ptr CDouble)

maxFitBytes :: Int
maxFitBytes = 16 * 1024 * 1024

decodeFit :: BS.ByteString -> IO (Either FitError DecodedFit)
decodeFit bytes
    | BS.length bytes > maxFitBytes = pure (Left FitResourceLimit)
    | otherwise = bracket acquire release (either (pure . Left) copy)
  where
    -- bracket masks the allocation handoff; asynchronous exceptions during the
    -- Haskell copy still release native memory. The safe native call itself is
    -- not interruptible; cancellation waits for bounded decoding to return.
    acquire = BS.useAsCStringLen bytes $ \(input, size) -> alloca $ \out -> do
        poke out nullPtr
        status <- cDecode (castPtr input) (fromIntegral size) out
        if status == 0 then Right <$> peek out else pure (Left (decodeError status))
    release = either (const (pure ())) cFree
    copy result = do
        summary <- cSummary result >>= peekArray 6
        count <- fromIntegral <$> cCount result
        records <- cRecords result >>= peekArray (count * 9)
        pure $ case fmap (\(CDouble x) -> x) summary of
            [start, end, elapsed, timer, distance, sport] -> do
                kind <- case sport of
                    1 -> Right FitCycling
                    2 -> Right FitRunning
                    _ -> Left FitAdapterFailure
                DecodedFit (FitSession kind start end (optional elapsed) (optional timer) (optional distance))
                    . V.fromList
                    <$> rows ((\(CDouble x) -> x) <$> records)
            _ -> Left FitAdapterFailure

-- Unwrap CDouble directly above: realToFrac may not preserve NaN sentinels
-- without optimization. Only the explicit ABI missing sentinel becomes Nothing.
optional :: Double -> Maybe Double
optional x = if isNaN x then Nothing else Just x

rows :: [Double] -> Either FitError [FitRecord]
rows [] = Right []
rows (time : heart : power : speed : distance : cadence : altitude : lat : lon : rest) =
    ( FitRecord
        time
        (optional heart)
        (optional power)
        (optional speed)
        (optional distance)
        (optional cadence)
        (optional altitude)
        (optional lat)
        (optional lon)
        :
    )
        <$> rows rest
rows _ = Left FitAdapterFailure

decodeError :: CInt -> FitError
decodeError status = case status of
    1 -> InvalidFit
    2 -> UnsupportedFit
    3 -> MissingFitTime
    4 -> FitResourceLimit
    _ -> FitAdapterFailure
