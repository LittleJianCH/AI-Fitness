{-# LANGUAGE OverloadedStrings #-}

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
import Data.Functor.Contravariant (contramap, (>$<))
import Data.Int (Int64)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import Data.Vector (Vector)
import qualified Hasql.Decoders as D
import qualified Hasql.Encoders as E
import Hasql.Statement (preparable)
import qualified Hasql.Transaction as T
import Storage.Codec
import Storage.Session.Types
import Storage.Types
import Storage.User.Types (UserId (..))

-- Used during login rotation; only one concurrent login may consume a cookie.
consumeSession :: TokenDigest -> UTCTime -> Store Bool
consumeSession digest now =
    lift $
        isJust
            <$> T.statement
                (digest, now)
                ( preparable
                    "UPDATE sessions SET revoked_at = GREATEST(created_at, $2, clock_timestamp()) WHERE token_digest = $1 AND revoked_at IS NULL \
                    \AND created_at <= $2 AND idle_expires_at > $2 AND absolute_expires_at > $2 RETURNING id"
                    ((fst >$< param digestValue) <> (snd >$< param E.timestamptz))
                    (D.rowMaybe (column D.uuid))
                )

touchSession :: TokenDigest -> UTCTime -> UTCTime -> Store ()
touchSession digest now expires =
    lift $
        T.statement (digest, now, expires) $
            preparable
                "UPDATE sessions SET last_seen_at = GREATEST(last_seen_at, $2), \
                \idle_expires_at = LEAST(absolute_expires_at, GREATEST(idle_expires_at, $3)) \
                \WHERE token_digest = $1 AND revoked_at IS NULL AND created_at <= $2 \
                \AND idle_expires_at > $2 AND absolute_expires_at > $2"
                ( ((\(d, _, _) -> d) >$< param digestValue)
                    <> ((\(_, n, _) -> n) >$< param E.timestamptz)
                    <> ((\(_, _, e) -> e) >$< param E.timestamptz)
                )
                D.noResult

listSessions :: UserId -> UTCTime -> Maybe (UTCTime, UUID) -> Int64 -> Store (Vector StoredSession)
listSessions uid now after limit =
    lift $
        T.statement (uid, now, after, limit) $
            preparable
                "SELECT id, user_id, token_digest, transport = 'browser', csrf_digest, device_name, \
                \created_at, last_seen_at, idle_expires_at, absolute_expires_at, revoked_at FROM sessions \
                \WHERE user_id = $1 AND revoked_at IS NULL AND created_at <= $2 AND idle_expires_at > $2 \
                \AND absolute_expires_at > $2 AND ($3::timestamptz IS NULL OR (created_at, id) < ($3,$4)) \
                \ORDER BY created_at DESC, id DESC LIMIT $5"
                ( ((\(u, _, _, _) -> u) >$< param userIdValue)
                    <> ((\(_, n, _, _) -> n) >$< param E.timestamptz)
                    <> ((\(_, _, a, _) -> fst <$> a) >$< E.param (E.nullable E.timestamptz))
                    <> ((\(_, _, a, _) -> snd <$> a) >$< E.param (E.nullable E.uuid))
                    <> ((\(_, _, _, l) -> l) >$< param E.int8)
                )
                (D.rowVector sessionRow)

createSession :: StoredSession -> Store ()
createSession value = ExceptT $ do
    inserted <-
        T.statement value $
            preparable
                "INSERT INTO sessions (id, user_id, token_digest, transport, csrf_digest, device_name, \
                \created_at, last_seen_at, idle_expires_at, absolute_expires_at, revoked_at) \
                \VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) ON CONFLICT DO NOTHING RETURNING id"
                ( (sessionId >$< param sessionIdValue)
                    <> (sessionUserId >$< E.param (E.nullable userIdValue))
                    <> (sessionTokenDigest >$< param digestValue)
                    <> (transportText . sessionTransport >$< param E.text)
                    <> (sessionCsrfDigest >$< E.param (E.nullable digestValue))
                    <> (sessionDeviceName >$< E.param (E.nullable E.text))
                    <> (sessionCreatedAt >$< param E.timestamptz)
                    <> (sessionLastSeenAt >$< param E.timestamptz)
                    <> (sessionIdleExpiresAt >$< param E.timestamptz)
                    <> (sessionAbsoluteExpiresAt >$< param E.timestamptz)
                    <> (sessionRevokedAt >$< E.param (E.nullable E.timestamptz))
                )
                (D.rowMaybe (column D.uuid))
    pure (if isJust inserted then Right () else Left SessionConflict)

-- A bootstrap session may have no user; callers must not turn it into a
-- Principal. This lookup does not extend expiry or implement authentication.
findActiveSession :: TokenDigest -> UTCTime -> Store (Maybe StoredSession)
findActiveSession digest now =
    lift $
        T.statement (digest, now) $
            preparable
                "SELECT s.id, s.user_id, s.token_digest, s.transport = 'browser', s.csrf_digest, s.device_name, \
                \s.created_at, s.last_seen_at, s.idle_expires_at, s.absolute_expires_at, s.revoked_at \
                \FROM sessions s LEFT JOIN users u ON u.id = s.user_id \
                \WHERE s.token_digest = $1 AND s.created_at <= $2 AND s.revoked_at IS NULL \
                \AND $2 < s.idle_expires_at AND $2 < s.absolute_expires_at \
                \AND (s.user_id IS NULL OR (u.disabled_at IS NULL AND u.created_at <= $2))"
                ((fst >$< param digestValue) <> (snd >$< param E.timestamptz))
                (D.rowMaybe sessionRow)

revokeSession :: UserId -> SessionId -> UTCTime -> Store Bool
revokeSession uid sid now =
    lift $
        isJust
            <$> T.statement
                (uid, sid, now)
                ( preparable
                    "UPDATE sessions SET revoked_at = COALESCE(revoked_at, GREATEST(created_at, $3, clock_timestamp())) WHERE user_id = $1 AND id = $2 RETURNING id"
                    ( ((\(u, _, _) -> u) >$< param userIdValue)
                        <> ((\(_, s, _) -> s) >$< param sessionIdValue)
                        <> ((\(_, _, t) -> t) >$< param E.timestamptz)
                    )
                    (D.rowMaybe (column D.uuid))
                )

revokeUserSessions :: UserId -> UTCTime -> Store Int64
-- The request's timestamp may predate a concurrent login that won the user
-- lock. Sample the DB clock at the write and never precede a row's creation.
revokeUserSessions uid now =
    lift $
        T.statement (uid, now) $
            preparable
                "UPDATE sessions SET revoked_at = GREATEST(created_at, $2, clock_timestamp()) WHERE user_id = $1 AND revoked_at IS NULL"
                ((fst >$< param userIdValue) <> (snd >$< param E.timestamptz))
                D.rowsAffected

sessionIdValue :: E.Value SessionId
sessionIdValue = contramap (\(SessionId value) -> value) E.uuid

digestValue :: E.Value TokenDigest
digestValue = contramap (\(TokenDigest value) -> value) E.bytea

transportText :: SessionTransport -> Text
transportText Browser = "browser"
transportText Native = "native"

sessionRow :: D.Row StoredSession
sessionRow =
    StoredSession . SessionId
        <$> column D.uuid
        <*> (fmap UserId <$> D.column (D.nullable D.uuid))
        <*> (TokenDigest <$> column D.bytea)
        <*> ((\browser -> if browser then Browser else Native) <$> column D.bool)
        <*> (fmap TokenDigest <$> D.column (D.nullable D.bytea))
        <*> D.column (D.nullable D.text)
        <*> column D.timestamptz
        <*> column D.timestamptz
        <*> column D.timestamptz
        <*> column D.timestamptz
        <*> D.column (D.nullable D.timestamptz)
