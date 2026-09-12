module App.Types (Settings (..), Environment (..), RequestContext (..), Authenticated (..)) where

import Auth.Password (Options)
import Control.Concurrent.MVar (MVar)
import Control.Concurrent.QSem (QSem)
import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Time (NominalDiffTime, UTCTime)
import Data.UUID.Types (UUID)
import Hasql.Pool (Pool)
import Network.Wai (Request)
import Storage.Session.Types (StoredSession)
import Storage.User.Types (PasswordHash, StoredUser)

data Settings = Settings
    { allowedOrigin :: ByteString
    , registrationOpen :: Bool
    , passwordOptions :: Options
    , browserIdle :: NominalDiffTime
    , browserAbsolute :: NominalDiffTime
    , nativeIdle :: NominalDiffTime
    , nativeAbsolute :: NominalDiffTime
    , authRequestsPerMinute :: Int
    , importRequestsPerMinute :: Int
    , maxJsonBytes :: Int
    }

data Environment = Environment
    { settings :: Settings
    , databasePool :: Pool
    , currentTime :: IO UTCTime
    , dummyPasswordHash :: PasswordHash
    , passwordWorkers :: QSem
    , cursorKey :: ByteString
    , authRateWindows :: MVar (Map ByteString (UTCTime, Int))
    , importRateWindows :: MVar (Map UUID (UTCTime, Int))
    }

data RequestContext = RequestContext
    { request :: Request
    , requestId :: Text
    }

data Authenticated = Authenticated
    { authenticatedUser :: StoredUser
    , authenticatedSession :: StoredSession
    }
