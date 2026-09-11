{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module HttpSupport
    ( call
    , rawCall
    , decoded
    , assert
    , bootstrap
    , browserHeaders
    , bearer
    , registerUser
    , loginNative
    , db
    , testPassword
    ) where

import qualified Api
import Api.Auth.Types
import Api.Common.Types (Problem (..))
import App.Types
import Control.Monad (unless, void, when)
import Data.Aeson (FromJSON, ToJSON, eitherDecode, encode)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text.Encoding as Text
import qualified Hasql.Pool as Pool
import Network.HTTP.Types
import Network.Wai (isSecure, requestHeaders, requestMethod)
import Network.Wai.Test
import qualified Storage.Database as Database
import Storage.Types

assert :: String -> Bool -> IO ()
assert label condition = unless condition (fail label)

call
    :: (ToJSON a) => Environment -> Method -> BS.ByteString -> RequestHeaders -> a -> Int -> IO SResponse
call env method path hs body = rawCall env method path ((hContentType, "application/json") : hs) (encode body)

rawCall
    :: Environment -> Method -> BS.ByteString -> RequestHeaders -> LBS.ByteString -> Int -> IO SResponse
rawCall environment method path hs body expected = do
    response <- runSession (srequest (SRequest req body)) (Api.application environment)
    assert
        ( BS8.unpack method
            <> " "
            <> BS8.unpack (BS.takeWhile (/= 63) path)
            <> ": expected "
            <> show expected
            <> ", got "
            <> show (statusCode (simpleStatus response))
        )
        (statusCode (simpleStatus response) == expected)
    assert
        "Response must disable caching"
        (lookup hCacheControl (simpleHeaders response) == Just "no-store")
    assert
        "Response must have request ID"
        (maybe False (not . BS.null) (lookup "X-Request-Id" (simpleHeaders response)))
    when (expected >= 400) $ do
        Problem _ _ rid _ <- decoded response
        assert
            "Error ID matches response header"
            (Just (Text.encodeUtf8 rid) == lookup "X-Request-Id" (simpleHeaders response))
    pure response
  where
    req = (setPath defaultRequest path) {requestMethod = method, requestHeaders = hs, isSecure = True}

decoded :: (FromJSON a) => SResponse -> IO a
decoded =
    either (const (fail "Response did not match the public JSON contract")) pure
        . eitherDecode
        . simpleBody

testPassword :: Text
testPassword = "synthetic-password-123"

bootstrap :: Environment -> IO (BS.ByteString, Text)
bootstrap environment = do
    response <- rawCall environment "GET" "/api/v1/auth/web/csrf" [] "" 200
    CsrfToken csrf <- decoded response
    cookie <-
        maybe (fail "Missing bootstrap cookie") pure (lookup "Set-Cookie" (simpleHeaders response))
    assert
        "Cookie security flags"
        ( all (`BS.isInfixOf` cookie) ["Secure", "HttpOnly", "SameSite=Lax", "Path=/"]
            && not ("Domain=" `BS.isInfixOf` cookie)
        )
    pure (BS.takeWhile (/= 59) cookie, csrf)

browserHeaders :: Environment -> (BS.ByteString, Text) -> RequestHeaders
browserHeaders env (cookie, csrf) =
    [ ("Cookie", cookie)
    , ("X-CSRF-Token", Text.encodeUtf8 csrf)
    , ("Origin", allowedOrigin (settings env))
    ]

bearer :: Text -> RequestHeaders
bearer token = [("Authorization", "Bearer " <> Text.encodeUtf8 token)]

registerUser :: Environment -> Text -> IO ()
registerUser env name = do
    session <- bootstrap env
    void
        ( call
            env
            "POST"
            "/api/v1/auth/register"
            (browserHeaders env session)
            (Registration name testPassword)
            201
        )

loginNative :: Environment -> Text -> Text -> IO NativeSession
loginNative env name password =
    call env "POST" "/api/v1/auth/native/login" [] (Credentials name password (Just "test device")) 200
        >>= decoded

db :: Environment -> Store a -> IO a
db env work = do
    result <- Pool.use (databasePool env) (Database.transaction work)
    case result of
        Right (Right value) -> pure value
        _ -> fail "HTTP test database operation failed"
