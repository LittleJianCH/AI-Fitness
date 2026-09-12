{-# LANGUAGE OverloadedStrings #-}

module Api.Error (problemError, problem, storage, errorFormatters) where

import Api.Common.Types (FieldError (..), Problem (..))
import App.Types
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (encode)
import Data.Either (fromRight)
import Data.Text (Text)
import qualified Hasql.Pool as Pool
import Servant
import qualified Storage.Database as Database
import Storage.Types
import qualified Workout.Validation.Types as Validation

problemError :: RequestContext -> Int -> Text -> Text -> ServerError
problemError context status code message =
    ServerError
        status
        ""
        (encode (Problem code message (requestId context) []))
        [("Content-Type", "application/json"), ("Cache-Control", "no-store")]

problem :: RequestContext -> Int -> Text -> Text -> Handler a
problem context status code message = throwError (problemError context status code message)

storage :: Environment -> RequestContext -> Store a -> Handler a
storage environment context work = do
    result <- liftIO (Pool.use (databasePool environment) (Database.transaction work))
    either translate pure (fromRight (Left DatabaseFailure) result)
  where
    translate DatabaseFailure = problem context 500 "internal_error" "Database operation failed"
    translate UserConflict = problem context 409 "registration_conflict" "Account cannot be registered"
    translate SessionConflict = problem context 409 "session_conflict" "Session state changed; retry the request"
    translate AuthenticationFailed = problem context 401 "unauthenticated" "Invalid or expired credentials"
    translate WorkoutConflict = problem context 409 "revision_conflict" "Workout changed; reload before editing"
    translate SubmissionConflict = problem context 409 "submission_conflict" "Submission ID was already used for different content"
    translate WorkoutNotManual = problem context 409 "reconciliation_required" "This workout requires source-aware deletion"
    translate WorkoutNotFound = problem context 404 "not_found" "Workout not found"
    translate (InvalidWorkout errors) =
        throwError
            (problemError context 422 "validation_failed" "Workout validation failed")
                { errBody =
                    encode
                        ( Problem
                            "validation_failed"
                            "Workout validation failed"
                            (requestId context)
                            [ FieldError (Validation.errorField err) "invalid_value" (Validation.errorMessage err) | err <- errors
                            ]
                        )
                }
    translate CorruptWorkout = problem context 500 "internal_error" "Stored workout cannot be read"
    translate ImportNotFound = problem context 404 "not_found" "Import not found"
    translate ImportConflict = problem context 409 "revision_conflict" "Import changed; reload before retrying"
    translate ImportReconciliationRequired = problem context 409 "reconciliation_required" "Source parts or published records changed"
    translate ImportRefreshRequired = problem context 409 "refresh_required" "Published imports require explicit refresh"
    translate ImportRetryRequired = problem context 409 "retry_required" "Failed imports require explicit retry"
    translate InvalidImport =
        problem
            context
            422
            "validation_failed"
            "Invalid HealthKit submission; this endpoint currently accepts one cycling or running part per object"
    translate CorruptImport = problem context 500 "internal_error" "Stored import cannot be read"

errorFormatters :: RequestContext -> ErrorFormatters
errorFormatters context =
    defaultErrorFormatters
        { bodyParserErrorFormatter = \_ _ _ -> problemError context 400 "invalid_request" "Invalid request body"
        , urlParseErrorFormatter = \_ _ _ -> problemError context 400 "invalid_query" "Invalid path or query parameter"
        , headerParseErrorFormatter = \_ _ _ -> problemError context 400 "invalid_request" "Invalid request header"
        , notFoundErrorFormatter = \_ -> problemError context 404 "not_found" "Route not found"
        }
