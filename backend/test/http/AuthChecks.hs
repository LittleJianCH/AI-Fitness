{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module AuthChecks (checks) where

import Api.Auth.Types
import Api.Common.Types (Id (..), Page (..), Problem (..))
import App.Types
import qualified Auth.Password as Password
import qualified Auth.Token as Token
import Control.Monad (forM_, void)
import Data.Aeson (object)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (isJust, isNothing)
import qualified Data.Text.Encoding as Text
import Data.Time (addUTCTime, diffUTCTime, getCurrentTime)
import qualified Data.UUID as UUID
import qualified Data.Vector as V
import HttpSupport
import Network.Wai.Test (simpleBody, simpleHeaders)
import qualified Storage.Session as Sessions
import qualified Storage.User as Users
import qualified Storage.User.Types as U

checks :: Environment -> IO ()
checks env = do
    begin <- getCurrentTime
    hash <- Password.hashPassword (passwordOptions (settings env)) testPassword
    assert "Argon2 verifies correct password" (Password.verifyPassword hash testPassword)
    assert "Argon2 rejects wrong password" (not (Password.verifyPassword hash "incorrect"))
    end <- getCurrentTime
    putStrLn ("Argon2 test-cost hash plus two verifications: " <> show (diffUTCTime end begin))
    void (rawCall env "GET" "/api/v1/auth/policy" [] "" 200)
    void (rawCall env "GET" "/api/v1/me" [] "" 401)
    bootstrapSession@(bootstrapCookie, _) <- bootstrap env
    void
        ( call
            env
            "POST"
            "/api/v1/auth/register"
            (browserHeaders env bootstrapSession)
            (Registration "auth.alice" testPassword)
            201
        )
    let closed = env {settings = (settings env) {registrationOpen = False}}
    void
        ( call
            closed
            "POST"
            "/api/v1/auth/register"
            (browserHeaders env bootstrapSession)
            (Registration "auth.closed" testPassword)
            403
        )
    void
        ( call
            env
            "POST"
            "/api/v1/auth/register"
            (browserHeaders env bootstrapSession)
            (Registration "auth.alice" testPassword)
            409
        )
    void
        ( call
            env
            "POST"
            "/api/v1/auth/web/login"
            [("Cookie", bootstrapCookie), ("X-CSRF-Token", "bad")]
            (Credentials "auth.alice" testPassword Nothing)
            403
        )
    response <-
        call
            env
            "POST"
            "/api/v1/auth/web/login"
            (browserHeaders env bootstrapSession)
            (Credentials "auth.alice" testPassword Nothing)
            200
    WebSession alice _ csrf <- decoded response
    cookie <-
        maybe
            (fail "Missing login cookie")
            (pure . BS.takeWhile (/= 59))
            (lookup "Set-Cookie" (simpleHeaders response))
    assert "Login rotates cookie" (cookie /= bootstrapCookie)
    reused <- rawCall env "GET" "/api/v1/auth/web/csrf" [("Cookie", cookie)] "" 200 >>= decoded
    assert "Authenticated CSRF reuse" (reused == CsrfToken csrf)
    void (rawCall env "GET" "/api/v1/me" [("Cookie", bootstrapCookie)] "" 401)
    current <- rawCall env "GET" "/api/v1/me" [("Cookie", cookie)] "" 200 >>= decoded
    assert "Browser identifies user" (current == alice)
    void
        ( call
            env
            "POST"
            "/api/v1/auth/native/login"
            [("Origin", "https://example.test")]
            (Credentials "auth.alice" testPassword Nothing)
            403
        )
    void
        ( call
            env
            "POST"
            "/api/v1/auth/native/login"
            [("Cookie", cookie)]
            (Credentials "auth.alice" testPassword Nothing)
            403
        )
    wrong <-
        call
            env
            "POST"
            "/api/v1/auth/native/login"
            []
            (Credentials "auth.alice" "wrong password" Nothing)
            401
            >>= decoded
    missing <-
        call
            env
            "POST"
            "/api/v1/auth/native/login"
            []
            (Credentials "auth.missing" "wrong password" Nothing)
            401
            >>= decoded
    let Problem wrongCode wrongMessage _ _ = wrong
        Problem missingCode missingMessage _ _ = missing
    assert
        "Login does not enumerate usernames"
        (wrongCode == missingCode && wrongMessage == missingMessage)
    NativeSession _ session token <- loginNative env "auth.alice" testPassword
    currentNative <- rawCall env "GET" "/api/v1/me" (bearer token) "" 200 >>= decoded
    assert "Native identifies user" (currentNative == alice)
    forM_ ["bearer", "bEaReR"] $ \scheme -> do
        user <-
            rawCall env "GET" "/api/v1/me" [("Authorization", scheme <> "  " <> Text.encodeUtf8 token)] "" 200
                >>= decoded
        assert "Bearer scheme is case-insensitive and permits multiple spaces" (user == alice)
    void
        ( rawCall
            env
            "GET"
            "/api/v1/me"
            [("Authorization", "Bearer " <> Text.encodeUtf8 token <> " extra")]
            ""
            401
        )
    void (rawCall env "GET" "/api/v1/me" (("Cookie", cookie) : bearer token) "" 401)
    void (rawCall env "GET" "/api/v1/me" (bearer token <> bearer token) "" 401)
    void
        ( rawCall
            env
            "GET"
            "/api/v1/me"
            [("Cookie", "__Host-ai-fitness-session=" <> Text.encodeUtf8 token)]
            ""
            401
        )
    let browserToken = Text.decodeUtf8 (BS.drop 1 (BS.dropWhile (/= 61) cookie))
    void (rawCall env "GET" "/api/v1/me" (bearer browserToken) "" 401)
    void (rawCall env "POST" "/api/v1/auth/logout" [("Cookie", cookie)] "" 403)
    void
        ( rawCall
            env
            "POST"
            "/api/v1/auth/logout"
            [("Cookie", cookie), ("X-CSRF-Token", Text.encodeUtf8 csrf), ("Origin", "https://evil.test")]
            ""
            403
        )
    Page first cursor <-
        rawCall env "GET" "/api/v1/auth/sessions?limit=1" (bearer token) "" 200 >>= decoded @(Page Session)
    assert "Session page is bounded" (V.length first == 1 && isJust cursor)
    next <- maybe (fail "Missing session cursor") pure cursor
    Page second _ <-
        rawCall
            env
            "GET"
            ("/api/v1/auth/sessions?limit=1&cursor=" <> Text.encodeUtf8 next)
            (bearer token)
            ""
            200
            >>= decoded @(Page Session)
    assert "Second session page" (V.length second == 1 && first /= second)
    void (rawCall env "GET" "/api/v1/auth/sessions?limit=101" (bearer token) "" 400)
    void
        ( rawCall
            env
            "GET"
            ("/api/v1/auth/sessions?cursor=" <> Text.encodeUtf8 (next <> "0"))
            (bearer token)
            ""
            400
        )
    void
        ( rawCall
            env
            "DELETE"
            "/api/v1/auth/sessions/00000000-0000-0000-0000-000000000001"
            (bearer token)
            ""
            404
        )
    let Session (Id sid) _ _ _ _ _ _ _ = session
    void
        ( rawCall
            env
            "DELETE"
            ("/api/v1/auth/sessions/" <> Text.encodeUtf8 (UUID.toText sid))
            (bearer token)
            ""
            204
        )
    void (rawCall env "GET" "/api/v1/me" (bearer token) "" 401)
    NativeSession _ _ secondToken <- loginNative env "auth.alice" testPassword
    let future = env {currentTime = addUTCTime (nativeAbsolute (settings env)) <$> currentTime env}
    void (rawCall future "GET" "/api/v1/me" (bearer secondToken) "" 401)
    let newPassword = "changed-synthetic-password-456"
    void
        ( call
            env
            "PUT"
            "/api/v1/auth/password"
            (bearer secondToken)
            (PasswordChange "incorrect" newPassword)
            401
        )
    void
        ( call
            env
            "PUT"
            "/api/v1/auth/password"
            (bearer secondToken)
            (PasswordChange testPassword newPassword)
            204
        )
    void (rawCall env "GET" "/api/v1/me" [("Cookie", cookie)] "" 401)
    void (rawCall env "GET" "/api/v1/me" (bearer secondToken) "" 401)
    void
        (call env "POST" "/api/v1/auth/native/login" [] (Credentials "auth.alice" testPassword Nothing) 401)
    NativeSession _ _ thirdToken <- loginNative env "auth.alice" newPassword
    void (rawCall env "DELETE" "/api/v1/auth/sessions" (bearer thirdToken) "" 204)
    void (rawCall env "GET" "/api/v1/me" (bearer thirdToken) "" 401)
    NativeSession _ _ lastToken <- loginNative env "auth.alice" newPassword
    logout <- rawCall env "POST" "/api/v1/auth/logout" (bearer lastToken) "" 204
    assert "204 has no JSON body" (simpleBody logout == "")
    now <- currentTime env
    stored <- db env (Users.findUserByUsername "auth.alice") >>= maybe (fail "Account missing") pure
    assert
        "Password persisted as Argon2id"
        (Password.verifyPassword (U.passwordHash stored) newPassword)
    active <- db env (Sessions.findActiveSession (Token.tokenDigest lastToken) now)
    assert "Logout revokes database record" (isNothing active)
    void
        (rawCall env "POST" "/api/v1/auth/native/login" [("Content-Type", "text/plain")] "password" 415)
    void (rawCall env "POST" "/api/v1/auth/native/login" [("Content-Type", "application/json")] "{" 400)
    void
        ( rawCall
            env
            "POST"
            "/api/v1/auth/native/login"
            [("Content-Type", "application/json")]
            ("\"" <> "not credentials" <> "\"")
            400
        )
    void
        ( rawCall
            env
            "POST"
            "/api/v1/auth/native/login"
            [("Content-Type", "application/json")]
            (LBS.replicate 16385 120)
            413
        )
    void (rawCall env "GET" "/unknown" [] "" 404)
    void (rawCall env "POST" "/api/v1/auth/policy" [] "" 405)
    let limited = env {settings = (settings env) {authRequestsPerMinute = 1}}
    response429 <-
        call
            limited
            "POST"
            "/api/v1/auth/native/login"
            []
            (Credentials "auth.alice" newPassword Nothing)
            429
    assert
        "Rate limit includes Retry-After"
        (lookup "Retry-After" (simpleHeaders response429) == Just "60")
    void (call env "POST" "/api/v1/auth/native/login" [] (object []) 400)
    putStrLn "HTTP authentication lifecycle, ownership, CSRF, expiry, errors and rate limits passed"
