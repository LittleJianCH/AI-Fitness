{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Api.Auth.Handlers (publicServer, privateServer) where

import Api.Auth.Routes
import Api.Auth.Types
import Api.Common.Routes (CookieResponse)
import Api.Common.Types (Id (..), Page (..))
import Api.Error (problem, storage)
import qualified Api.Pagination as Pagination
import App.Types
import qualified Auth.Password as Password
import Auth.Request
import Auth.Session
import qualified Auth.Token as Token
import Control.Monad (unless, void)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (throwE)
import Data.Aeson (toJSON)
import Data.Char (isAlphaNum, isAscii)
import Data.Maybe (isNothing)
import qualified Data.Text as Text
import qualified Data.UUID.V4 as UUID
import Import.Fit.Decode (maxFitBytes)
import Servant
import qualified Storage.Codec as Storage
import qualified Storage.Session as Sessions
import qualified Storage.Session.Types as S
import Storage.Types
import qualified Storage.User as Users
import qualified Storage.User.Types as U

publicServer :: Environment -> RequestContext -> Server PublicAuthAPI
publicServer environment context = policy :<|> csrf :<|> webLogin :<|> nativeLogin :<|> register
  where
    policy =
        respond
            ( WithStatus @200
                ( AuthPolicy
                    (if registrationOpen (settings environment) then OpenRegistration else ClosedRegistration)
                    8
                    128
                    (fromIntegral maxFitBytes)
                )
            )
    csrf = do
        rateLimit environment context
        existing <- credential context
        now <- liftIO (currentTime environment)
        found <- case existing of
            Nothing -> pure Nothing
            Just (S.Native, _) -> problem context 401 "unauthenticated" "A browser session is required"
            Just (S.Browser, token) -> do
                session <- storage environment context (Sessions.findActiveSession (Token.tokenDigest token) now)
                pure ((,) token <$> session)
        (token, _) <- case found of
            Just pair@(_, session) | S.sessionTransport session == S.Browser -> pure pair
            _ -> do
                pair@(_, session) <- newSession environment Nothing S.Browser Nothing
                storage environment context (Sessions.createSession session)
                pure pair
        respond (cookieResponse (sessionCookie token) (WithStatus @200 (CsrfToken (Token.csrfToken token))))
    webLogin _ credentials = do
        rateLimit environment context
        (oldToken, _) <- activeBrowser environment context
        (user, token, session) <- login S.Browser (Just oldToken) credentials
        respond
            ( cookieResponse
                (sessionCookie token)
                ( WithStatus @200
                    (WebSession (userView user) (sessionView (S.sessionId session) session) (Token.csrfToken token))
                )
            )
    nativeLogin credentials = do
        rateLimit environment context
        nativeRequest context
        (user, token, session) <- login S.Native Nothing credentials
        respond
            (WithStatus @200 (NativeSession (userView user) (sessionView (S.sessionId session) session) token))
    login transport previous (Credentials name password device) = do
        unless (validUsername name && Text.length password <= 128) invalidLogin
        unless (maybe True (\value -> Text.length value <= 100 && Storage.validText value) device) $
            problem context 422 "validation_failed" "Device name is too long or contains U+0000"
        account <- storage environment context (Users.findUserByUsername name)
        verified <-
            passwordWork
                environment
                ( pure
                    (Password.verifyPassword (maybe (dummyPasswordHash environment) U.passwordHash account) password)
                )
        user <- case account of
            Just user | verified && isNothing (U.userDisabledAt user) -> pure user
            _ -> invalidLogin
        (token, session) <- newSession environment (Just (U.userId user)) transport device
        now <- liftIO (currentTime environment)
        storage environment context $ do
            locked <- Users.lockUser (U.userId user) >>= maybe (throwE AuthenticationFailed) pure
            unless (U.passwordHash locked == U.passwordHash user && isNothing (U.userDisabledAt locked)) $
                throwE AuthenticationFailed
            case previous of
                Nothing -> pure ()
                Just old -> do
                    consumed <- Sessions.consumeSession (Token.tokenDigest old) now
                    unless consumed (throwE AuthenticationFailed)
            Sessions.createSession session
        pure (user, token, session)
    invalidLogin = problem context 401 "unauthenticated" "Invalid username or password"
    register _ (Registration name password) = do
        rateLimit environment context
        void (activeBrowser environment context)
        unless (registrationOpen (settings environment)) $
            problem context 403 "registration_closed" "Registration is disabled"
        unless (validUsername name && validPassword password) $
            problem context 422 "validation_failed" "Username or password does not satisfy the policy"
        hashed <-
            passwordWork environment (Password.hashPassword (passwordOptions (settings environment)) password)
        uid <- U.UserId <$> liftIO UUID.nextRandom
        now <- liftIO (currentTime environment)
        let user = U.StoredUser uid name hashed now Nothing
        storage environment context (Users.createUser user)
        respond (WithStatus @201 (userView user))

privateServer :: Environment -> RequestContext -> Principal -> Server PrivateAuthAPI
privateServer environment context principal = me :<|> logout :<|> sessions :<|> revoke :<|> revokeAll :<|> changePassword
  where
    me =
        owned environment context principal (pure . userView . authenticatedUser)
            >>= respond . WithStatus @200
    logout = do
        now <- liftIO (currentTime environment)
        owned environment context principal $ \auth ->
            void
                ( Sessions.revokeSession
                    (U.userId (authenticatedUser auth))
                    (S.sessionId (authenticatedSession auth))
                    now
                )
        cleared
    sessions cursor limit = do
        count <- Pagination.pageLimit context limit
        let scope = toJSON ("sessions" :: Text.Text, principalUserId principal)
        after <- Pagination.readCursor environment context scope cursor
        now <- liftIO (currentTime environment)
        values <- owned environment context principal $ \auth -> Sessions.listSessions (U.userId (authenticatedUser auth)) now after (fromIntegral (count + 1))
        let position session = let S.SessionId sid = S.sessionId session in (S.sessionCreatedAt session, sid)
            Page rows next = Pagination.page count (Pagination.writeCursor environment scope . position) values
            Id current = principalSessionId principal
        respond (WithStatus @200 (Page (sessionView (S.SessionId current) <$> rows) next))
    revoke (Id sid) = do
        now <- liftIO (currentTime environment)
        found <- owned environment context principal $ \auth -> Sessions.revokeSession (U.userId (authenticatedUser auth)) (S.SessionId sid) now
        unless found $ problem context 404 "not_found" "Session not found"
        respond (WithStatus @204 NoContent)
    revokeAll = do
        now <- liftIO (currentTime environment)
        owned environment context principal $ \auth -> void (Sessions.revokeUserSessions (U.userId (authenticatedUser auth)) now)
        cleared
    changePassword (PasswordChange current next) = do
        rateLimit environment context
        unless (validPassword next && Text.length current <= 128) $
            problem context 422 "validation_failed" "Password does not satisfy the policy"
        user <- owned environment context principal (pure . authenticatedUser)
        verified <- passwordWork environment (pure (Password.verifyPassword (U.passwordHash user) current))
        unless verified $ problem context 401 "unauthenticated" "Invalid current password"
        hashed <-
            passwordWork environment (Password.hashPassword (passwordOptions (settings environment)) next)
        now <- liftIO (currentTime environment)
        owned environment context principal $ \auth -> do
            unless (U.passwordHash (authenticatedUser auth) == U.passwordHash user) $
                throwE AuthenticationFailed
            Users.changePassword (U.userId user) hashed
            void (Sessions.revokeUserSessions (U.userId user) now)
        cleared
    cleared = respond (cookieResponse clearCookie (WithStatus @204 NoContent))

cookieResponse :: Text.Text -> a -> CookieResponse a
cookieResponse cookie = addHeader cookie . addHeader ("no-store" :: Text.Text)

validUsername :: Text.Text -> Bool
validUsername name =
    Text.length name >= 3
        && Text.length name <= 64
        && Text.all (\c -> isAscii c && (isAlphaNum c || c `elem` ("_.-" :: String))) name

validPassword :: Text.Text -> Bool
validPassword value = Text.length value >= 8 && Text.length value <= 128
