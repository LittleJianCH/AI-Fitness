{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module Api.Binary (FitFile (..)) where

import qualified Data.ByteString.Lazy as ByteString
import Data.OpenApi (NamedSchema (..), ToSchema (..), binarySchema)
import Servant (MimeRender (..), MimeUnrender (..), OctetStream)

newtype FitFile = FitFile ByteString.ByteString

instance MimeRender OctetStream FitFile where
    mimeRender _ (FitFile bytes) = bytes

instance MimeUnrender OctetStream FitFile where
    mimeUnrender _ = Right . FitFile

instance ToSchema FitFile where
    declareNamedSchema _ = pure (NamedSchema (Just "FitFile") binarySchema)
