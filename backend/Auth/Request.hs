{-# LANGUAGE OverloadedStrings #-}

module Auth.Request (credential, browserToken, nativeRequest, checkCsrf, sessionCookie, clearCookie, rateLimit) where

import Api.Error (problem, problemError)
import App.Types
import qualified Auth.Token as Token
import Control.Concurrent.MVar (modifyMVar)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import Data.Char (toLower)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text.Encoding as Text
import Data.Time (diffUTCTime)
import Network.HTTP.Types (HeaderName)
import Network.Socket (SockAddr (..))
import Network.Wai (remoteHost, requestHeaders)
import Servant (Handler, errHeaders, throwError)
import Storage.Session.Types
import Web.Cookie

headers :: HeaderName -> RequestContext -> [BS.ByteString]
headers name = fmap snd . filter ((== name) . fst) . requestHeaders . request

cookies :: RequestContext -> [BS.ByteString]
cookies =
    fmap snd
        . concatMap (filter ((== "__Host-ai-fitness-session") . fst) . parseCookies)
        . headers "Cookie"

credential :: RequestContext -> Handler (Maybe (SessionTransport, Text))
credential context = case (cookies context, headers "Authorization" context) of
    ([], []) -> pure Nothing
    ([token], []) -> Just . (,) Browser <$> decode token
    ([], [authorization]) -> case BS8.words authorization of
        [scheme, token] | BS8.map toLower scheme == "bearer" -> Just . (,) Native <$> decode token
        _ -> invalid
    _ -> problem context 401 "unauthenticated" "Ambiguous credentials"
  where
    decode token = if Token.validToken token then pure (Text.decodeUtf8 token) else invalid
    invalid = problem context 401 "unauthenticated" "Invalid credentials"

browserToken :: RequestContext -> Handler Text
browserToken context =
    credential context
        >>= maybe invalid (\(transport, value) -> if transport == Browser then pure value else invalid)
  where
    invalid = problem context 403 "csrf_failed" "A browser session is required"

nativeRequest :: RequestContext -> Handler ()
nativeRequest context =
    unless
        ( null (headers "Origin" context)
            && null (cookies context)
            && null (headers "Sec-Fetch-Site" context)
            && null (headers "Authorization" context)
        )
        $ problem
            context
            403
            "forbidden"
            "Native login does not accept browser credentials or browser-origin requests"

checkCsrf :: Environment -> RequestContext -> StoredSession -> Handler ()
checkCsrf environment context session =
    unless valid $
        problem context 403 "csrf_failed" "Origin or CSRF token is invalid"
  where
    valid =
        headers "Origin" context == [allowedOrigin (settings environment)] && case (headers "X-CSRF-Token" context, sessionCsrfDigest session) of
            ([token], Just expected) | Token.validToken token -> Token.equalDigest expected (Token.tokenDigest (Text.decodeUtf8 token))
            _ -> False

sessionCookie :: Text -> Text
sessionCookie token =
    Text.decodeUtf8 $
        renderSetCookieBS
            defaultSetCookie
                { setCookieName = "__Host-ai-fitness-session"
                , setCookieValue = Text.encodeUtf8 token
                , setCookiePath = Just "/"
                , setCookieSecure = True
                , setCookieHttpOnly = True
                , setCookieSameSite = Just sameSiteLax
                }

clearCookie :: Text
clearCookie = sessionCookie "" <> "; Max-Age=0"

-- Direct peer address only: forwarded headers require an explicitly trusted
-- reverse-proxy policy. Ignore the source port so reconnecting cannot evade it.
rateLimit :: Environment -> RequestContext -> Handler ()
rateLimit environment context = do
    now <- liftIO (currentTime environment)
    let address = BS8.pack $ case remoteHost (request context) of
            SockAddrInet _ host -> show host
            SockAddrInet6 _ _ host _ -> show host
            SockAddrUnix path -> path
        perPeer = authRequestsPerMinute (settings environment)
    accepted <- liftIO $ modifyMVar (authRateWindows environment) $ \windows -> do
        let live = Map.filter (\(since, _) -> diffUTCTime now since < 60) windows
            (started, count) = Map.findWithDefault (now, 0) address live
            total = sum (snd <$> Map.elems live)
            accept = count < perPeer && total < perPeer * 10 && Map.size live < 10000
        pure (if accept then Map.insert address (started, count + 1) live else live, accept)
    unless accepted $
        throwError
            (problemError context 429 "rate_limited" "Too many authentication requests")
                { errHeaders =
                    [("Content-Type", "application/json"), ("Cache-Control", "no-store"), ("Retry-After", "60")]
                }
