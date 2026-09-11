{-# LANGUAGE OverloadedStrings #-}

module Storage.Database (withConnection, transaction, runTransaction) where

import Control.Exception (bracket)
import Control.Monad (when)
import Control.Monad.Trans.Except (runExceptT)
import Data.Either (fromRight, isLeft)
import Data.Text (Text)
import qualified Hasql.Connection as Connection
import qualified Hasql.Connection.Settings as Settings
import qualified Hasql.Session as Session
import qualified Hasql.Transaction as Transaction
import qualified Hasql.Transaction.Sessions as Sessions
import Storage.Types (StorageError (..), Store)

-- CLI/test connection lifetime. The Session below also runs in IHP's Hasql pool.
withConnection :: Text -> (Connection.Connection -> IO a) -> IO a
withConnection url action = bracket acquire Connection.release $ \connection -> do
    configured <- Connection.use connection (Session.script "SET TIME ZONE 'UTC'")
    either (const (fail "Database initialization failed")) (const (action connection)) configured
  where
    acquire =
        Connection.acquire (Settings.connectionString url)
            >>= either (const (fail "Database connection failed")) pure

-- A domain failure rolls back earlier writes too. Returning Left alone would
-- otherwise COMMIT a successful SQL transaction containing a failed operation.
transaction :: Store a -> Session.Session (Either StorageError a)
transaction work = Sessions.transaction Sessions.ReadCommitted Sessions.Write $ do
    result <- runExceptT work
    when (isLeft result) Transaction.condemn
    pure result

runTransaction :: Connection.Connection -> Store a -> IO (Either StorageError a)
runTransaction connection work = fromRight (Left DatabaseFailure) <$> Connection.use connection (transaction work)
