{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Api.Analysis.Handlers (server) where

import Analysis.Fatigue.Request
import Api.Analysis.Routes (AnalysisAPI)
import Api.Auth.Types (Principal)
import Api.Error (problem)
import qualified Api.Workout.Types as Api
import App.Types
import Auth.Session (owned)
import Control.Monad.Trans.Except (throwE)
import qualified Data.Vector as V
import Servant
import qualified Storage.Settings as Settings
import Storage.Types (StorageError (..))
import Storage.User.Types (userId)
import qualified Storage.Workout as Workouts
import qualified Storage.Workout.Query as Query
import Storage.Workout.Types (WorkoutFilter (..))

server :: Environment -> RequestContext -> Principal -> Server AnalysisAPI
server environment context principal request = do
    days <- either (problem context 422 "validation_failed") pure (validateRequest request)
    case days of
        [] -> problem context 422 "validation_failed" "Calendar must contain at least one day"
        (_, firstDay) : rest -> do
            let lastDay = foldl' (\_ (_, entry) -> entry) firstDay rest
            (settings, workouts) <- owned environment context principal $ \auth -> do
                let uid = userId (authenticatedUser auth)
                    query = WorkoutFilter (Just (calendarStart firstDay)) (Just (calendarEnd lastDay)) Nothing Nothing
                cards <- Query.listWorkouts uid query Nothing 1001
                if V.length cards > 1000
                    then throwE AnalysisTooLarge
                    else do
                        settings <- Settings.load uid
                        workouts <-
                            traverse
                                (\card -> Workouts.loadWorkout uid (Api._id card) >>= maybe (throwE WorkoutNotFound) pure)
                                cards
                        pure (settings, workouts)
            result <-
                either
                    (problem context 422 "analysis_unavailable")
                    pure
                    (calculateHistory settings request (V.toList workouts))
            respond (WithStatus @200 result)
