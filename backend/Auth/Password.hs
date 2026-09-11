{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

module Auth.Password (Options, options, hashPassword, verifyPassword) where

import Data.ByteArray (constEq)
import Data.ByteArray.Encoding (Base (Base64), convertFromBase, convertToBase)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Storage.User.Types (PasswordHash (..))
import Text.Read (readMaybe)
import "crypton" Crypto.Error (CryptoFailable (..))
import qualified "crypton" Crypto.KDF.Argon2 as Argon
import "crypton" Crypto.Random (getRandomBytes)

newtype Options = Options Argon.Options

options :: Int -> Int -> Maybe Options
options memory iterations
    | memory >= 19456 && memory <= 262144 && iterations >= 2 && iterations <= 10 =
        Just
            ( Options
                (Argon.Options (fromIntegral iterations) (fromIntegral memory) 1 Argon.Argon2id Argon.Version13)
            )
    | otherwise = Nothing

hashPassword :: Options -> Text -> IO PasswordHash
hashPassword configuration@(Options config) password = do
    salt <- getRandomBytes 16
    case derive configuration password salt of
        CryptoFailed _ -> fail "Password hashing failed"
        CryptoPassed value ->
            pure $
                PasswordHash $
                    "$argon2id$v=19$m="
                        <> decimal (Argon.memory config)
                        <> ",t="
                        <> decimal (Argon.iterations config)
                        <> ",p=1$"
                        <> base64 salt
                        <> "$"
                        <> base64 value
  where
    decimal = Text.pack . show

verifyPassword :: PasswordHash -> Text -> Bool
verifyPassword (PasswordHash encoded) password
    | Text.length encoded > 512 || Text.length password > 128 = False
    | otherwise = case parseHash encoded of
        Nothing -> False
        Just (config, salt, expected) -> case derive config password salt of
            CryptoFailed _ -> False
            CryptoPassed actual -> actual `constEq` expected

derive :: Options -> Text -> BS.ByteString -> CryptoFailable BS.ByteString
derive (Options config) password salt = Argon.hash config (Text.encodeUtf8 password) salt 32

parseHash :: Text -> Maybe (Options, BS.ByteString, BS.ByteString)
parseHash encoded = case Text.splitOn "$" encoded of
    ["", "argon2id", "v=19", parameters, saltText, hashText] -> do
        config <- case Text.splitOn "," parameters of
            [m, t, "p=1"] -> do
                memory <- Text.stripPrefix "m=" m >>= readMaybe . Text.unpack
                iterations <- Text.stripPrefix "t=" t >>= readMaybe . Text.unpack
                options memory iterations
            _ -> Nothing
        salt <- decode64 saltText
        value <- decode64 hashText
        if BS.length salt == 16 && BS.length value == 32
            then Just (config, salt, value)
            else Nothing
    _ -> Nothing

base64 :: BS.ByteString -> Text
base64 = Text.dropWhileEnd (== '=') . Text.decodeUtf8 . convertToBase Base64

decode64 :: Text -> Maybe BS.ByteString
decode64 text =
    either (const Nothing) Just $
        convertFromBase
            Base64
            (Text.encodeUtf8 (text <> Text.replicate ((4 - Text.length text `mod` 4) `mod` 4) "="))
