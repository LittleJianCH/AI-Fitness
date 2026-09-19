{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.Settings (load, save) where

import Api.Settings.Codec ()
import Control.Monad.Trans.Except (ExceptT (..), throwE)
import Data.Aeson (Result (..), fromJSON, toJSON)
import Data.Coerce (coerce)
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import qualified Profile.Settings as Settings
import Profile.Types
import Storage.Types
import Storage.User.Types (UserId (..))

load :: UserId -> Store UserSettings
load uid = ExceptT $ do
    row <-
        T.statement
            (coerce uid)
            [TH.maybeStatement|
        SELECT payload :: jsonb FROM user_settings WHERE user_id = $1 :: uuid AND storage_version = 1
    |]
    pure $ case row of
        Nothing -> Right Settings.emptySettings
        Just value -> case fromJSON value of
            Success settings | null (Settings.validate settings) -> Right settings
            _ -> Left CorruptSettings

-- Callers hold the authenticated account lock in this transaction. A revision
-- check plus that lock serializes initial creation as well as subsequent writes.
save :: UserId -> UserSettings -> Store UserSettings
save uid proposed = do
    current <- load uid
    if settingsRevision current /= settingsRevision proposed
        then throwE SettingsConflict
        else case Settings.replace current proposed of
            Left errors -> throwE (InvalidSettings errors)
            Right next -> ExceptT $ do
                T.statement
                    (coerce uid, toJSON next)
                    [TH.resultlessStatement|
                    INSERT INTO user_settings (user_id, storage_version, payload)
                    VALUES ($1 :: uuid, 1, $2 :: jsonb)
                    ON CONFLICT (user_id) DO UPDATE SET payload = EXCLUDED.payload
                |]
                pure (Right next)
