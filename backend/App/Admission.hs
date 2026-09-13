module App.Admission (Admission, newAdmission, withAdmission) where

import Control.Concurrent.MVar (MVar, modifyMVar, modifyMVar_, newMVar)
import Control.Exception (bracket)
import Control.Monad (when)

newtype Admission = Admission (MVar Int)

newAdmission :: Int -> IO Admission
newAdmission capacity
    | capacity > 0 = Admission <$> newMVar capacity
    | otherwise = fail "Admission capacity must be positive"

-- Reject immediately instead of queuing bodies in memory. bracket masks the
-- acquisition/release boundary and restores cancellation during the action.
withAdmission :: Admission -> IO a -> IO (Maybe a)
withAdmission (Admission slots) action = bracket acquire release run
  where
    acquire = modifyMVar slots $ \available ->
        pure (if available > 0 then (available - 1, True) else (available, False))
    release acquired = when acquired (modifyMVar_ slots (pure . (+ 1)))
    run acquired = if acquired then Just <$> action else pure Nothing
