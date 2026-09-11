{-# LANGUAGE OverloadedStrings #-}

module Storage.User (createUser, loadUser, findUserByUsername) where

import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..))
import Data.Functor.Contravariant ((>$<))
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Hasql.Decoders as D
import qualified Hasql.Encoders as E
import Hasql.Statement (preparable)
import qualified Hasql.Transaction as T
import Storage.Codec
import Storage.Types
import Storage.User.Types

createUser :: StoredUser -> Store ()
createUser user = ExceptT $ do
    inserted <-
        T.statement user $
            preparable
                "INSERT INTO users (id, username, password_hash, created_at, disabled_at) \
                \VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING RETURNING id"
                ( (userId >$< param userIdValue)
                    <> (username >$< param E.text)
                    <> ((\u -> let PasswordHash value = passwordHash u in value) >$< param E.text)
                    <> (userCreatedAt >$< param E.timestamptz)
                    <> (userDisabledAt >$< E.param (E.nullable E.timestamptz))
                )
                (D.rowMaybe userIdColumn)
    pure (if isJust inserted then Right () else Left UserConflict)

loadUser :: UserId -> Store (Maybe StoredUser)
loadUser uid =
    lift $
        T.statement uid $
            preparable
                "SELECT id, username, password_hash, created_at, disabled_at FROM users WHERE id = $1"
                (param userIdValue)
                (D.rowMaybe userRow)

-- Authentication-only lookup: usernames are exact and case-sensitive.
findUserByUsername :: Text -> Store (Maybe StoredUser)
findUserByUsername name =
    lift $
        T.statement name $
            preparable
                "SELECT id, username, password_hash, created_at, disabled_at FROM users WHERE username = $1"
                (param E.text)
                (D.rowMaybe userRow)

userRow :: D.Row StoredUser
userRow =
    StoredUser
        <$> userIdColumn
        <*> column D.text
        <*> (PasswordHash <$> column D.text)
        <*> column D.timestamptz
        <*> D.column (D.nullable D.timestamptz)
