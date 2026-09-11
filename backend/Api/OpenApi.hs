{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Api.OpenApi (openApi) where

import Api.Auth.Context (SessionAuth)
import Api.Types (API)
import Control.Lens (Traversal', ix, preview, (&), (.~), (?~))
import Data.OpenApi
import Data.Proxy (Proxy (..))
import Network.HTTP.Types (statusCode)
import Servant (AuthProtect, HasStatus (..), Headers, NoContent, UVerb, Verb, statusOf, (:>))
import Servant.OpenApi (HasOpenApi (..))

-- Upstream UVerb resolves a polymorphic Verb instance and drops Headers.
-- Derive the header-bearing response with the concrete Verb instance, then
-- substitute that response into the otherwise unchanged UVerb specification.
instance
    ( HasStatus a
    , HasOpenApi (UVerb method contentTypes (a ': rest))
    , HasOpenApi (Verb method (StatusOf a) contentTypes (Headers headers a))
    )
    => HasOpenApi (UVerb method contentTypes (Headers headers a ': rest))
    where
    toOpenApi _ = case preview responseAtStatus headerDocument of
        Nothing -> base
        Just response -> base & responseAtStatus .~ response
      where
        base = toOpenApi (Proxy :: Proxy (UVerb method contentTypes (a ': rest)))
        headerDocument = toOpenApi (Proxy :: Proxy (Verb method (StatusOf a) contentTypes (Headers headers a)))
        responseAtStatus :: Traversal' OpenApi (Referenced Response)
        responseAtStatus = allOperations . responses . responses . ix (statusCode (statusOf (Proxy :: Proxy a)))

instance ToSchema NoContent where
    declareNamedSchema _ = pure (NamedSchema Nothing mempty)

-- Servant deliberately leaves AuthProtect's transport unspecified. This one
-- instance documents our session boundary; it does not authenticate requests.
instance (HasOpenApi api) => HasOpenApi (AuthProtect SessionAuth :> api) where
    toOpenApi _ =
        toOpenApi (Proxy :: Proxy api)
            & allOperations . security
                .~ [SecurityRequirement [("sessionCookie", [])], SecurityRequirement [("sessionBearer", [])]]

openApi :: OpenApi
openApi =
    toOpenApi (Proxy :: Proxy API)
        & info . title .~ "AI Fitness API"
        & info . version .~ "1.0.0-draft.1"
        & info . description
            ?~ "Contract definitions only. Product routes are not mounted until authentication and real handlers are implemented. All private resources are scoped to the authenticated user."
        & components . securitySchemes
            .~ SecurityDefinitions
                [
                    ( "sessionCookie"
                    , SecurityScheme
                        (SecuritySchemeApiKey (ApiKeyParams "__Host-ai-fitness-session" ApiKeyCookie))
                        ( Just
                            "Opaque browser session cookie. Unsafe requests additionally require X-CSRF-Token and a valid Origin."
                        )
                    )
                ,
                    ( "sessionBearer"
                    , SecurityScheme
                        (SecuritySchemeHttp (HttpSchemeBearer Nothing))
                        (Just "Opaque native session token, not a JWT. Never send both Cookie and Authorization credentials.")
                    )
                ]
