{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Workout.Routes (WorkoutAPI, WorkoutListAPI, WorkoutDetailAPI, PowerCurveAPI, WorkoutAnalysisAPI) where

import Api.Common.Routes
import Api.Common.Types
import Api.Workout.Types
import Data.Text (Text)
import Servant
import Workout.Identity.Types (WorkoutGroupId, WorkoutId, WorkoutRevision)

type WorkoutListAPI =
    Summary "List workout summaries ordered by start time descending, then ID descending"
        :> QueryParam "from" Timestamp
        :> QueryParam "before" Timestamp
        :> QueryParam "sport" SportFilter
        :> QueryParam "tag" Text
        :> QueryParam "groupId" WorkoutGroupId
        :> Pagination (Response 'GET 200 (Page WorkoutCard))

type WorkoutDetailAPI =
    Summary "Read the complete canonical workout including independent sample streams"
        :> Response 'GET 200 Workout

type PowerCurveAPI =
    "power-curve"
        :> Summary
            "Best time-weighted power for fixed durations; linear interpolation across gaps at most five seconds"
        :> Response 'GET 200 PowerCurve

type WorkoutAnalysisAPI =
    "analysis"
        :> Summary
            "Revision-bound sensor statistics, distributions, power analysis, distance splits and running dynamics"
        :> Response 'GET 200 WorkoutAnalysis

type WorkoutAPI =
    "workouts"
        :> ( WorkoutListAPI
                :<|> Summary "Create a manual workout; the submission ID makes retries idempotent"
                    :> ReqBody '[JSON] ManualWorkout
                    :> Response 'POST 200 Workout
                :<|> Capture "workoutId" WorkoutId
                    :> ( WorkoutDetailAPI
                            :<|> PowerCurveAPI
                            :<|> WorkoutAnalysisAPI
                            :<|> "user-data"
                                :> Summary "Replace editable metadata with optimistic concurrency control"
                                :> ReqBody '[JSON] EditWorkout
                                :> Response 'PUT 200 Workout
                            :<|> Summary "Delete the workout, detach group memberships and suppress its source import"
                                :> QueryParam' '[Required, Strict] "expectedRevision" WorkoutRevision
                                :> (QueryParam' '[Required, Strict] "deleteEmptyGroups" Bool :> Response 'DELETE 204 NoContent)
                       )
           )
