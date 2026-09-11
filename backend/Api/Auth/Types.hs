{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Api.Auth.Types
    ( User (..)
    , Credentials (..)
    , Registration (..)
    , RegistrationPolicy (..)
    , AuthPolicy (..)
    , Session (..)
    , SessionTransport (..)
    , WebSession (..)
    , NativeSession (..)
    , CsrfToken (..)
    , PasswordChange (..)
    , Principal (..)
    ) where

import Api.Codec (ViaJSON (..))
import Api.Common.Types
import Data.Aeson (FromJSON, ToJSON)
import Data.Int (Int32)
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import GHC.Generics (Generic)

data User = User {_id :: Id "User", _username :: Text, _createdAt :: Timestamp}
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON User)

data Credentials = Credentials {_username :: Text, _password :: Text, _deviceName :: Maybe Text}
    deriving stock (Eq, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON Credentials)

data Registration = Registration {_username :: Text, _password :: Text}
    deriving stock (Eq, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON Registration)

data RegistrationPolicy = OpenRegistration | ClosedRegistration
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON RegistrationPolicy)

data AuthPolicy = AuthPolicy
    { _registration :: RegistrationPolicy
    , _minimumPasswordLength :: Int32
    , _maximumPasswordLength :: Int32
    , _maximumFitBytes :: Int32
    }
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON AuthPolicy)

data SessionTransport = Browser | Native
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON SessionTransport)

data Session = Session
    { _id :: Id "Session"
    , _deviceName :: Maybe Text
    , _transport :: SessionTransport
    , _createdAt :: Timestamp
    , _lastSeenAt :: Timestamp
    , _idleExpiresAt :: Timestamp
    , _absoluteExpiresAt :: Timestamp
    , _current :: Bool
    }
    deriving stock (Eq, Show, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON Session)

data WebSession = WebSession {_user :: User, _session :: Session, _csrfToken :: Text}
    deriving stock (Eq, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON WebSession)

data NativeSession = NativeSession {_user :: User, _session :: Session, _token :: Text}
    deriving stock (Eq, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON NativeSession)

newtype CsrfToken = CsrfToken {_csrfToken :: Text}
    deriving stock (Eq, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON CsrfToken)

data PasswordChange = PasswordChange {_currentPassword :: Text, _newPassword :: Text}
    deriving stock (Eq, Generic)
    deriving (FromJSON, ToJSON, ToSchema) via (ViaJSON PasswordChange)

-- Server-only context supplied after credential validation; never a request DTO.
data Principal = Principal
    { principalUserId :: Id "User"
    , principalSessionId :: Id "Session"
    , principalTransport :: SessionTransport
    }
    deriving (Eq, Show)
