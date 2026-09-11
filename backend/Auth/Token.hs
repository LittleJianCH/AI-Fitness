{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

module Auth.Token (newToken, tokenDigest, csrfToken, validToken, sign, encodeHex, decodeHex, equalDigest) where

import Data.ByteArray (constEq, convert)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text.Encoding as Text
import Storage.Session.Types (TokenDigest (..))
import "crypton" Crypto.Hash (Digest, SHA256, hash)
import "crypton" Crypto.MAC.HMAC (HMAC, hmac)
import "crypton" Crypto.Random (getRandomBytes)

newToken :: IO Text
newToken = encodeHex <$> (getRandomBytes 32 :: IO BS.ByteString)

tokenDigest :: Text -> TokenDigest
tokenDigest value = TokenDigest (convert (hash (Text.encodeUtf8 value) :: Digest SHA256))

-- Reproducible from the presented HttpOnly cookie, so GET csrf need not persist
-- a plaintext CSRF token or rotate it out from under another browser tab.
csrfToken :: Text -> Text
csrfToken cookie = encodeHex (sign (Text.encodeUtf8 cookie) "ai-fitness/csrf/v1")

validToken :: BS.ByteString -> Bool
validToken value = BS.length value == 64 && BS.all hexadecimal value
  where
    hexadecimal c = (c >= 48 && c <= 57) || (c >= 97 && c <= 102)

sign :: BS.ByteString -> BS.ByteString -> BS.ByteString
sign key message = convert (hmac key message :: HMAC SHA256)

encodeHex :: BS.ByteString -> Text
encodeHex = Text.decodeUtf8 . convertToBase Base16

decodeHex :: Text -> Maybe BS.ByteString
decodeHex = either (const Nothing) Just . convertFromBase Base16 . Text.encodeUtf8

equalDigest :: TokenDigest -> TokenDigest -> Bool
equalDigest (TokenDigest left) (TokenDigest right) = left `constEq` right
