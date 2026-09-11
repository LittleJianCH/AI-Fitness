{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import Api.Common.Routes (CookieResponse, Response)
import Api.Common.Types (Revision (..))
import Api.Export.Types (Platform (..))
import Api.Workout.Routes (WorkoutDetailAPI, WorkoutListAPI)
import ContractFixtures
import Control.Monad (unless)
import Data.Aeson (eitherDecode, encode)
import qualified Data.ByteString.Lazy as ByteString
import Data.Either (isLeft)
import Data.Text (Text)
import Network.HTTP.Types (status200, status204, status400)
import Network.Wai (defaultRequest, requestMethod)
import Network.Wai.Test (request, runSession, setPath, simpleBody, simpleHeaders, simpleStatus)
import Servant
import Workout.Types (WorkoutId, WorkoutRevision (..), WorkoutUserData)

type FixtureAPI =
    ( "api"
        :> "v1"
        :> "workouts"
        :> (WorkoutListAPI :<|> Capture "workoutId" WorkoutId :> WorkoutDetailAPI)
    )
        :<|> "fixture-no-content" :> Response 'DELETE 204 (CookieResponse NoContent)

-- Test-only handlers exercise the real Servant router and MIME encoders. They
-- are never linked into the production application and do not implement auth.
application :: Application
application = serve (Proxy :: Proxy FixtureAPI) ((listHandler :<|> detailHandler) :<|> respond emptyResponse)
  where
    listHandler :: Server WorkoutListAPI
    listHandler _ _ _ _ _ _ limit =
        if limit == Just 0
            then respond (WithStatus @400 failure)
            else respond (WithStatus @200 workoutPage)
    detailHandler :: WorkoutId -> Server WorkoutDetailAPI
    detailHandler _ = respond (WithStatus @200 workout)
    emptyResponse
        :: Headers '[Header "Set-Cookie" Text, Header "Cache-Control" Text] (WithStatus 204 NoContent)
    emptyResponse = addHeader "fixture=; Max-Age=0" (addHeader "no-store" (WithStatus @204 NoContent))

main :: IO ()
main = do
    ok <- runSession (request (setPath defaultRequest "/api/v1/workouts")) application
    bad <- runSession (request (setPath defaultRequest "/api/v1/workouts?limit=0")) application
    detail <-
        runSession
            (request (setPath defaultRequest "/api/v1/workouts/00000000-0000-0000-0000-000000000000"))
            application
    emptyResponse <-
        runSession
            (request ((setPath defaultRequest "/fixture-no-content") {requestMethod = "DELETE"}))
            application
    ensure
        (simpleStatus ok == status200 && simpleStatus bad == status400 && simpleStatus detail == status200)
        "Servant response status mismatch"
    ensure
        ( simpleStatus emptyResponse == status204
            && ByteString.null (simpleBody emptyResponse)
            && lookup "Set-Cookie" (simpleHeaders emptyResponse) == Just "fixture=; Max-Age=0"
            && lookup "Cache-Control" (simpleHeaders emptyResponse) == Just "no-store"
        )
        "Empty responses must retain headers without a body"
    ByteString.writeFile "build/list-response.json" (simpleBody ok)
    ByteString.writeFile "build/error-response.json" (simpleBody bad)
    ByteString.writeFile "build/workout-response.json" (simpleBody detail)
    ByteString.writeFile "build/export-response.json" (encode exportBundle)
    ensure (eitherDecode (simpleBody detail) == Right workout) "Workout JSON round trip failed"
    ensure
        (eitherDecode (encode runningWorkout) == Right runningWorkout)
        "Running JSON round trip failed"
    ensure
        (eitherDecode (encode exportBundle) == Right exportBundle)
        "Canonical export JSON round trip failed"
    ensure
        (encode AppleHealth == "\"appleHealth\"" && eitherDecode "\"appleHealth\"" == Right AppleHealth)
        "Single-option enum must be a string"
    ensure
        (isLeft (eitherDecode "9007199254740993" :: Either String WorkoutRevision))
        "Numeric revisions must be rejected"
    ensure
        (isLeft (eitherDecode "\"01\"" :: Either String Revision))
        "Noncanonical revisions must be rejected"
    ensure
        (eitherDecode "\"9007199254740993\"" == Right (WorkoutRevision 9007199254740993))
        "Revision lost precision"
    ensure
        ( isLeft
            ( eitherDecode
                "{\"workoutTitle\":null,\"workoutTags\":[],\"statisticsInclusion\":\"includeInStatistics\"}"
                :: Either String WorkoutUserData
            )
        )
        "Null optional fields must be rejected"
    putStrLn "Servant contract responses and JSON boundary checks passed."

ensure :: Bool -> String -> IO ()
ensure condition message = unless condition (fail message)
