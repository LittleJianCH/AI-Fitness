{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.User (createUser, loadUser, lockUser, changePassword, findUserByUsername) where

import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..))
import Data.Coerce (coerce)
import Data.Maybe (isJust)
import Data.Profunctor (dimap, lmap, rmap)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import Storage.Types
import Storage.User.Types

-- Login and account-wide revocation use the same lock as password changes.
lockUser :: UserId -> Store (Maybe StoredUser)
lockUser uid =
    lift $
        T.statement uid $
            dimap
                coerce
                (fmap userRow)
                [TH.maybeStatement|
                    SELECT id :: uuid, username :: text, password_hash :: text,
                           created_at :: timestamptz, disabled_at :: timestamptz?
                    FROM users WHERE id = $1 :: uuid FOR UPDATE
                |]

changePassword :: UserId -> PasswordHash -> Store ()
changePassword uid value =
    lift $
        T.statement (uid, value) $
            lmap
                coerce
                [TH.resultlessStatement|
                    UPDATE users SET password_hash = $2 :: text WHERE id = $1 :: uuid
                |]

createUser :: StoredUser -> Store ()
createUser user = ExceptT $ do
    inserted <-
        T.statement user $
            lmap
                (\u -> (coerce (userId u), username u, coerce (passwordHash u), userCreatedAt u, userDisabledAt u))
                [TH.maybeStatement|
                    INSERT INTO users (id, username, password_hash, created_at, disabled_at)
                    VALUES ($1 :: uuid, $2 :: text, $3 :: text, $4 :: timestamptz, $5 :: timestamptz?)
                    ON CONFLICT DO NOTHING RETURNING id :: uuid
                |]
    pure (if isJust inserted then Right () else Left UserConflict)

loadUser :: UserId -> Store (Maybe StoredUser)
loadUser uid =
    lift $
        T.statement uid $
            dimap
                coerce
                (fmap userRow)
                [TH.maybeStatement|
                    SELECT id :: uuid, username :: text, password_hash :: text,
                           created_at :: timestamptz, disabled_at :: timestamptz?
                    FROM users WHERE id = $1 :: uuid
                |]

-- Authentication-only lookup: usernames are exact and case-sensitive.
findUserByUsername :: Text -> Store (Maybe StoredUser)
findUserByUsername name =
    lift $
        T.statement name $
            rmap
                (fmap userRow)
                [TH.maybeStatement|
                    SELECT id :: uuid, username :: text, password_hash :: text,
                           created_at :: timestamptz, disabled_at :: timestamptz?
                    FROM users WHERE username = $1 :: text
                |]

userRow :: (UUID, Text, Text, UTCTime, Maybe UTCTime) -> StoredUser
userRow (uid, name, password, created, disabled) =
    StoredUser (UserId uid) name (PasswordHash password) created disabled
