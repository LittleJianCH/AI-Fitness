{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api.Analysis.Routes (AnalysisAPI) where

import Analysis.Fatigue.Request
import Api.Analysis.Codec ()
import Api.Common.Routes (Response)
import Servant

type AnalysisAPI =
    "analysis"
        :> "training-history"
        :> Summary
            "Owner-scoped HRSS fitness and fatigue with explicit calendar, history completeness and initial state"
        :> ReqBody '[JSON] TrainingHistoryRequest
        :> Response 'POST 200 TrainingHistory
