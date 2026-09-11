{-# LANGUAGE OverloadedStrings #-}

module Auth.Session (authenticate, activeBrowser, newSession, owned, userView, sessionView, passwordWork) where

import qualified Api.Auth.Types as Api
import Api.Common.Types (Id (..), Timestamp (..))
import Api.Error (problem, storage)
import App.Types
import Auth.Request (browserToken, checkCsrf, credential)
import qualified Auth.Token as Token
import Control.Concurrent.QSem (signalQSem, waitQSem)
import Control.Exception (bracket_, evaluate)
import Control.Monad (unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (throwE)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Time (addUTCTime)
import qualified Data.UUID.V4 as UUID
import Network.Wai (requestMethod)
import Servant (Handler)
import qualified Storage.Session as Sessions
import Storage.Session.Types
import Storage.Types
import qualified Storage.User as Users
import Storage.User.Types

passwordWork :: Environment -> IO a -> Handler a
passwordWork environment work = liftIO $ bracket_ (waitQSem workers) (signalQSem workers) (work >>= evaluate)
  where
    workers = passwordWorkers environment

authenticate :: Environment -> RequestContext -> Handler Api.Principal
authenticate environment context = do
    (transport, token) <- credential context >>= maybe unauthenticated pure
    now <- liftIO (currentTime environment)
    session <-
        storage environment context (Sessions.findActiveSession (Token.tokenDigest token) now)
            >>= maybe unauthenticated pure
    unless (sessionTransport session == transport) unauthenticated
    UserId uid <- maybe unauthenticated pure (sessionUserId session)
    when (transport == Browser && requestMethod (request context) `notElem` ["GET", "HEAD", "OPTIONS"]) $
        checkCsrf environment context session
    let idle = if transport == Browser then browserIdle else nativeIdle
    storage
        environment
        context
        (Sessions.touchSession (Token.tokenDigest token) now (addUTCTime (idle (settings environment)) now))
    let SessionId sid = sessionId session
    pure (Api.Principal (Id uid) (Id sid) (if transport == Browser then Api.Browser else Api.Native))
  where
    unauthenticated = problem context 401 "unauthenticated" "Invalid or expired credentials"

activeBrowser :: Environment -> RequestContext -> Handler (Text, StoredSession)
activeBrowser environment context = do
    token <- browserToken context
    now <- liftIO (currentTime environment)
    session <-
        storage environment context (Sessions.findActiveSession (Token.tokenDigest token) now)
            >>= maybe (problem context 403 "csrf_failed" "Browser session expired") pure
    unless (sessionTransport session == Browser) $
        problem context 403 "csrf_failed" "A browser session is required"
    checkCsrf environment context session
    pure (token, session)

newSession
    :: Environment -> Maybe UserId -> SessionTransport -> Maybe Text -> Handler (Text, StoredSession)
newSession environment uid transport device = do
    token <- liftIO Token.newToken
    sid <- liftIO UUID.nextRandom
    now <- liftIO (currentTime environment)
    let config = settings environment
        (idle, absolute) =
            if transport == Browser
                then (browserIdle config, browserAbsolute config)
                else (nativeIdle config, nativeAbsolute config)
        csrf = if transport == Browser then Just (Token.tokenDigest (Token.csrfToken token)) else Nothing
    pure
        ( token
        , StoredSession
            (SessionId sid)
            uid
            (Token.tokenDigest token)
            transport
            csrf
            device
            now
            now
            (addUTCTime idle now)
            (addUTCTime absolute now)
            Nothing
        )

-- Recheck after taking the account lock. Mutations, login, password change and
-- account-wide revocation share this transaction order.
owned :: Environment -> RequestContext -> Api.Principal -> (Authenticated -> Store a) -> Handler a
owned environment context principal work = do
    (_, token) <-
        credential context >>= maybe (problem context 401 "unauthenticated" "Credentials required") pure
    now <- liftIO (currentTime environment)
    storage environment context $ do
        user <- Users.lockUser uid >>= maybe (throwE AuthenticationFailed) pure
        session <-
            Sessions.findActiveSession (Token.tokenDigest token) now
                >>= maybe (throwE AuthenticationFailed) pure
        unless
            (isNothing (userDisabledAt user) && sessionUserId session == Just uid && sessionId session == sid)
            $ throwE AuthenticationFailed
        work (Authenticated user session)
  where
    Id userUuid = Api.principalUserId principal
    Id sessionUuid = Api.principalSessionId principal
    uid = UserId userUuid
    sid = SessionId sessionUuid

userView :: StoredUser -> Api.User
userView user =
    let UserId uid = userId user in Api.User (Id uid) (username user) (Timestamp (userCreatedAt user))

sessionView :: SessionId -> StoredSession -> Api.Session
sessionView current session =
    let SessionId sid = sessionId session
     in Api.Session
            (Id sid)
            (sessionDeviceName session)
            (if sessionTransport session == Browser then Api.Browser else Api.Native)
            (Timestamp (sessionCreatedAt session))
            (Timestamp (sessionLastSeenAt session))
            (Timestamp (sessionIdleExpiresAt session))
            (Timestamp (sessionAbsoluteExpiresAt session))
            (sessionId session == current)
