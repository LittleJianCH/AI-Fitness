{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Storage.Session
    ( createSession
    , findActiveSession
    , consumeSession
    , touchSession
    , listSessions
    , revokeSession
    , revokeUserSessions
    ) where

import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..))
import Data.ByteString (ByteString)
import Data.Coerce (coerce)
import Data.Int (Int64)
import Data.Maybe (isJust)
import Data.Profunctor (dimap, lmap)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import Data.Vector (Vector)
import qualified Hasql.TH as TH
import qualified Hasql.Transaction as T
import Storage.Session.Types
import Storage.Types
import Storage.User.Types (UserId (..))

-- Used during login rotation; only one concurrent login may consume a cookie.
consumeSession :: TokenDigest -> UTCTime -> Store Bool
consumeSession digest now =
    lift $
        T.statement (digest, now) $
            dimap
                coerce
                isJust
                [TH.maybeStatement|
                    UPDATE sessions SET revoked_at = GREATEST(created_at, $2 :: timestamptz, clock_timestamp())
                    WHERE token_digest = $1 :: bytea AND revoked_at IS NULL
                      AND created_at <= $2 :: timestamptz AND idle_expires_at > $2 :: timestamptz
                      AND absolute_expires_at > $2 :: timestamptz
                    RETURNING id :: uuid
                |]

touchSession :: TokenDigest -> UTCTime -> UTCTime -> Store ()
touchSession digest now expires =
    lift $
        T.statement (digest, now, expires) $
            lmap
                coerce
                [TH.resultlessStatement|
                    UPDATE sessions SET last_seen_at = GREATEST(last_seen_at, $2 :: timestamptz),
                        idle_expires_at = LEAST(absolute_expires_at, GREATEST(idle_expires_at, $3 :: timestamptz))
                    WHERE token_digest = $1 :: bytea AND revoked_at IS NULL AND created_at <= $2 :: timestamptz
                      AND idle_expires_at > $2 :: timestamptz AND absolute_expires_at > $2 :: timestamptz
                |]

listSessions :: UserId -> UTCTime -> Maybe (UTCTime, UUID) -> Int64 -> Store (Vector StoredSession)
listSessions uid now after limit =
    lift $
        T.statement (uid, now, after, limit) $
            dimap
                (\(u, n, a, l) -> (coerce u, n, fst <$> a, snd <$> a, l))
                (fmap sessionRow)
                [TH.vectorStatement|
                    SELECT id :: uuid, user_id :: uuid?, token_digest :: bytea,
                           (transport = 'browser') :: bool, csrf_digest :: bytea?, device_name :: text?,
                           created_at :: timestamptz, last_seen_at :: timestamptz,
                           idle_expires_at :: timestamptz, absolute_expires_at :: timestamptz,
                           revoked_at :: timestamptz?
                    FROM sessions
                    WHERE user_id = $1 :: uuid AND revoked_at IS NULL AND created_at <= $2 :: timestamptz
                      AND idle_expires_at > $2 :: timestamptz AND absolute_expires_at > $2 :: timestamptz
                      AND ($3 :: timestamptz? IS NULL OR (created_at, id) < ($3 :: timestamptz?, $4 :: uuid?))
                    ORDER BY created_at DESC, id DESC LIMIT $5 :: int8
                |]

createSession :: StoredSession -> Store ()
createSession value = ExceptT $ do
    inserted <-
        T.statement value $
            lmap
                ( \s ->
                    ( coerce (sessionId s)
                    , coerce (sessionUserId s)
                    , coerce (sessionTokenDigest s)
                    , transportText (sessionTransport s)
                    , coerce (sessionCsrfDigest s)
                    , sessionDeviceName s
                    , sessionCreatedAt s
                    , sessionLastSeenAt s
                    , sessionIdleExpiresAt s
                    , sessionAbsoluteExpiresAt s
                    , sessionRevokedAt s
                    )
                )
                [TH.maybeStatement|
                    INSERT INTO sessions (id, user_id, token_digest, transport, csrf_digest, device_name,
                        created_at, last_seen_at, idle_expires_at, absolute_expires_at, revoked_at)
                    VALUES ($1 :: uuid, $2 :: uuid?, $3 :: bytea, $4 :: text, $5 :: bytea?, $6 :: text?,
                            $7 :: timestamptz, $8 :: timestamptz, $9 :: timestamptz, $10 :: timestamptz,
                            $11 :: timestamptz?)
                    ON CONFLICT DO NOTHING RETURNING id :: uuid
                |]
    pure (if isJust inserted then Right () else Left SessionConflict)

-- A bootstrap session may have no user; callers must not turn it into a
-- Principal. This lookup does not extend expiry or implement authentication.
findActiveSession :: TokenDigest -> UTCTime -> Store (Maybe StoredSession)
findActiveSession digest now =
    lift $
        T.statement (digest, now) $
            dimap
                coerce
                (fmap sessionRow)
                [TH.maybeStatement|
                    SELECT s.id :: uuid, s.user_id :: uuid?, s.token_digest :: bytea,
                           (s.transport = 'browser') :: bool, s.csrf_digest :: bytea?, s.device_name :: text?,
                           s.created_at :: timestamptz, s.last_seen_at :: timestamptz,
                           s.idle_expires_at :: timestamptz, s.absolute_expires_at :: timestamptz,
                           s.revoked_at :: timestamptz?
                    FROM sessions s LEFT JOIN users u ON u.id = s.user_id
                    WHERE s.token_digest = $1 :: bytea AND s.created_at <= $2 :: timestamptz AND s.revoked_at IS NULL
                      AND $2 :: timestamptz < s.idle_expires_at AND $2 :: timestamptz < s.absolute_expires_at
                      AND (s.user_id IS NULL OR (u.disabled_at IS NULL AND u.created_at <= $2 :: timestamptz))
                |]

revokeSession :: UserId -> SessionId -> UTCTime -> Store Bool
revokeSession uid sid now =
    lift $
        T.statement (uid, sid, now) $
            dimap
                coerce
                isJust
                [TH.maybeStatement|
                    UPDATE sessions SET revoked_at = COALESCE(revoked_at,
                        GREATEST(created_at, $3 :: timestamptz, clock_timestamp()))
                    WHERE user_id = $1 :: uuid AND id = $2 :: uuid RETURNING id :: uuid
                |]

revokeUserSessions :: UserId -> UTCTime -> Store Int64
-- The request's timestamp may predate a concurrent login that won the user
-- lock. Sample the DB clock at the write and never precede a row's creation.
revokeUserSessions uid now =
    lift $
        T.statement (uid, now) $
            lmap
                coerce
                [TH.rowsAffectedStatement|
                    UPDATE sessions SET revoked_at = GREATEST(created_at, $2 :: timestamptz, clock_timestamp())
                    WHERE user_id = $1 :: uuid AND revoked_at IS NULL
                |]

transportText :: SessionTransport -> Text
transportText Browser = "browser"
transportText Native = "native"

sessionRow
    :: ( UUID
       , Maybe UUID
       , ByteString
       , Bool
       , Maybe ByteString
       , Maybe Text
       , UTCTime
       , UTCTime
       , UTCTime
       , UTCTime
       , Maybe UTCTime
       )
    -> StoredSession
sessionRow (sid, uid, digest, browser, csrf, device, created, seen, idle, absolute, revoked) =
    StoredSession
        (SessionId sid)
        (UserId <$> uid)
        (TokenDigest digest)
        (if browser then Browser else Native)
        (TokenDigest <$> csrf)
        device
        created
        seen
        idle
        absolute
        revoked
