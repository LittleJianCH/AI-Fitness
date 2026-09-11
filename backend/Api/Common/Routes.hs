{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Api.Common.Routes (Response, Pagination, ExpectedRevision, CookieResponse) where

import Api.Common.Types (Problem, Revision)
import Data.Int (Int32)
import Data.Text (Text)
import Servant

type Response method status a =
    UVerb
        method
        '[JSON]
        '[ AtStatus status a
         , WithStatus 400 Problem
         , WithStatus 401 Problem
         , WithStatus 403 Problem
         , WithStatus 404 Problem
         , WithStatus 409 Problem
         , WithStatus 413 Problem
         , WithStatus 422 Problem
         , Headers '[Header "Retry-After" Int32] (WithStatus 429 Problem)
         , WithStatus 500 Problem
         ]

-- Headers must stay outside WithStatus for Servant's OpenAPI instance to retain
-- both the status code and the response header definitions.
type family AtStatus status a where
    AtStatus status (Headers headers a) = Headers headers (WithStatus status a)
    AtStatus status a = WithStatus status a

type Pagination api =
    QueryParam "cursor" Text :> QueryParam "limit" Int32 :> api

type ExpectedRevision api = QueryParam' '[Required, Strict] "expectedRevision" Revision :> api

type CookieResponse a = Headers '[Header "Set-Cookie" Text, Header "Cache-Control" Text] a
