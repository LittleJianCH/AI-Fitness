{-# LANGUAGE OverloadedStrings #-}

module HistoryRequestTests (cases) where

import Analysis.Fatigue.Request
import AnalysisFixtures (epoch)
import Data.Either (isLeft, isRight)
import Data.Time (addUTCTime)
import qualified Data.Vector as V
import Profile.Settings (emptySettings)

cases :: [(String, Bool)]
cases =
    [
        ( "history request: unknown recording remains unknown"
        , case calculateHistory emptySettings request [] of
            Right result -> all ((== Nothing) . trainingFitness) (trainingDays result)
            _ -> False
        )
    ,
        ( "history request: explicitly complete rest has known zero"
        , case calculateHistory emptySettings complete [] of
            Right result -> all ((== Just 0) . trainingFitness) (trainingDays result)
            _ -> False
        )
    ,
        ( "history request: initial state is explicit"
        , isLeft (validateRequest (request {historyAssumeNoPriorLoad = False}))
        )
    ,
        ( "history request: conflicting initial assumptions rejected"
        , isLeft (validateRequest (request {historyPriorFitness = Just 0, historyPriorFatigue = Just 0}))
        )
    ,
        ( "history request: nonfinite initial load rejected"
        , isLeft
            ( validateRequest
                ( request
                    { historyAssumeNoPriorLoad = False
                    , historyPriorFitness = Just (1 / 0)
                    , historyPriorFatigue = Just 0
                    }
                )
            )
        )
    ,
        ( "history request: calendar gaps rejected"
        , isLeft
            ( validateRequest
                ( request
                    { historyCalendar =
                        V.fromList
                            [ day
                            , day
                                { calendarDate = "2026-09-14"
                                , calendarStart = addUTCTime 172800 epoch
                                , calendarEnd = addUTCTime 259200 epoch
                                }
                            ]
                    }
                )
            )
        )
    ,
        ( "history request: empty range rejected"
        , isLeft (validateRequest (request {historyCalendar = V.empty}))
        )
    ,
        ( "history request: duplicate labels rejected"
        , isLeft (validateRequest (request {historyCalendar = V.fromList [day, day]}))
        )
    ,
        ( "history request: supports 23-hour calendar days"
        , case validateRequest
            (request {historyCalendar = V.singleton (day {calendarEnd = addUTCTime (23 * 3600) epoch})}) of
            Right _ -> True
            _ -> False
        )
    ,
        ( "history request: rejects boundaries shifted 47 hours from date"
        , isLeft
            ( validateRequest
                ( request
                    { historyCalendar =
                        V.singleton
                            (day {calendarStart = addUTCTime (47 * 3600) epoch, calendarEnd = addUTCTime (71 * 3600) epoch})
                    }
                )
            )
        )
    ,
        ( "history request: validates end against following midnight"
        , isLeft
            ( validateRequest
                ( request
                    { historyCalendar =
                        V.singleton
                            (day {calendarStart = addUTCTime (12 * 3600) epoch, calendarEnd = addUTCTime (37 * 3600) epoch})
                    }
                )
            )
        )
    ,
        ( "history request: supports UTC plus 14 and minus 12"
        , all
            ( \offset ->
                isRight
                    ( validateRequest
                        ( request
                            { historyCalendar =
                                V.singleton
                                    (day {calendarStart = addUTCTime offset epoch, calendarEnd = addUTCTime (86400 + offset) epoch})
                            }
                        )
                    )
            )
            [-(14 * 3600), 12 * 3600]
        )
    ]
  where
    day = CalendarDay "2026-09-12" epoch (addUTCTime 86400 epoch) False
    request = TrainingHistoryRequest (V.singleton day) True Nothing Nothing
    complete = request {historyCalendar = V.singleton (day {calendarRecordingComplete = True})}
