module Storage.User.Types (UserId (..), PasswordHash (..), StoredUser (..)) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)

newtype UserId = UserId UUID deriving (Eq, Ord, Show)

-- Encoded Argon2id PHC string produced/verified by the future auth service.
-- No Show instance: account records must not leak credential material.
newtype PasswordHash = PasswordHash Text deriving (Eq)

data StoredUser = StoredUser
    { userId :: UserId
    , username :: Text
    , passwordHash :: PasswordHash
    , userCreatedAt :: UTCTime
    , userDisabledAt :: Maybe UTCTime
    }
    deriving (Eq)
