module Storage.Session.Types
    ( SessionId (..)
    , TokenDigest (..)
    , SessionTransport (..)
    , StoredSession (..)
    ) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import Storage.User.Types (UserId)

newtype SessionId = SessionId UUID deriving (Eq, Ord, Show)

-- SHA-256 digest of a random secret, never a raw token. No Show instance.
newtype TokenDigest = TokenDigest ByteString deriving (Eq)

data SessionTransport = Browser | Native deriving (Eq, Show)

data StoredSession = StoredSession
    { sessionId :: SessionId
    , sessionUserId :: Maybe UserId
    , sessionTokenDigest :: TokenDigest
    , sessionTransport :: SessionTransport
    , sessionCsrfDigest :: Maybe TokenDigest
    , sessionDeviceName :: Maybe Text
    , sessionCreatedAt :: UTCTime
    , sessionLastSeenAt :: UTCTime
    , sessionIdleExpiresAt :: UTCTime
    , sessionAbsoluteExpiresAt :: UTCTime
    , sessionRevokedAt :: Maybe UTCTime
    }
    deriving (Eq)
