{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.WorkoutGroup.Routes (WorkoutGroupAPI) where

import Api.Common.Routes
import Api.Common.Types
import Api.WorkoutGroup.Types
import Servant
import Workout.Identity.Types (WorkoutGroupId)

type WorkoutGroupAPI =
    "workout-groups"
        :> ( Pagination (Response 'GET 200 (Page GroupView))
                :<|> Summary "Create a group from ordered owned workout IDs; retries use the submission ID"
                    :> ReqBody '[JSON] CreateGroup
                    :> Response 'POST 200 GroupView
                :<|> Capture "groupId" WorkoutGroupId
                    :> ( Response 'GET 200 GroupView
                            :<|> Summary "Replace group metadata and membership atomically"
                                :> ReqBody '[JSON] EditGroup
                                :> Response 'PUT 200 GroupView
                            :<|> Summary "Delete a group without deleting its workouts"
                                :> ExpectedRevision (Response 'DELETE 204 NoContent)
                       )
           )
