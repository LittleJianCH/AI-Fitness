{-# LANGUAGE OverloadedStrings #-}

module WorkoutTests (cases) where

import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.UUID.Types as UUID
import qualified Data.Vector as V
import Fixtures
import Workout.Empty
import qualified Workout.Sport as Sport
import Workout.Types
import Workout.Update
import Workout.Validation

cases :: [(String, Bool)]
cases =
    [ ("representative cycling record preserves available metrics", null (validateWorkout workout))
    , ("valid sparse streams need not share timestamps", V.length (Sport.heartRate (Cycling ride)) == 2)
    , ("real zero power survives", (value <$> (Sport.power (Cycling ride) V.!? 0)) == Just (Power 0))
    ,
        ( "missing manual samples do not become zeroes"
        , null (validateWorkout (withSport (Cycling emptyCycling)))
        )
    , ("running is supported", null (validateWorkout (withSport (Running emptyRunning))))
    ,
        ( "duplicate measurement timestamps rejected"
        , badHeart [Timed start (HeartRate 120), Timed start (HeartRate 121)]
        )
    ,
        ( "out-of-order measurements rejected"
        , badHeart [Timed (at 2) (HeartRate 120), Timed start (HeartRate 121)]
        )
    , ("out-of-range sample rejected", badHeart [Timed (at (-1)) (HeartRate 120)])
    , ("NaN rejected", badHeart [Timed start (HeartRate (0 / 0))])
    , ("infinity rejected", badHeart [Timed start (HeartRate (1 / 0))])
    , ("missing heart rate is not a zero sample", badHeart [Timed start (HeartRate 0)])
    ,
        ( "cumulative distance resets rejected"
        , badMotion
            emptyMotion {motionDistance = V.fromList [Timed start (Distance 10), Timed (at 1) (Distance 0)]}
        )
    ,
        ( "latitude range checked"
        , badMotion emptyMotion {motionPosition = V.singleton (Timed start (Position 91 0))}
        )
    ,
        ( "percentage bounds checked"
        , invalidCycling
            ride
                { cyclingPedaling =
                    (cyclingPedaling ride) {leftPowerShare = V.singleton (Timed start (Percentage 101))}
                }
        )
    , ("lap cannot extend beyond workout", invalidCycling ride {cyclingLaps = V.singleton outsideLap})
    ,
        ( "duplicate extension keys rejected"
        , invalidWorkout
            workout
                { workoutObservation =
                    observation
                        { observationExtensions = observationExtensions observation V.++ observationExtensions observation
                        }
                }
        )
    ,
        ( "empty time range rejected"
        , not (null (validateWorkout (withSportRange (TimeRange start start) (Running emptyRunning))))
        )
    , ("group members independent of temporal continuity", null (validateGroup group))
    ,
        ( "duplicate group members rejected"
        , not (null (validateGroup group {workoutGroupMembers = wid :| [wid]}))
        )
    , ("nil identities rejected", not (null (validateWorkout workout {workoutId = WorkoutId UUID.nil})))
    ,
        ( "refresh preserves identity and user content"
        , case replaceObservation (WorkoutRevision 1) observation workout of
            Right w ->
                workoutId w == wid
                    && workoutUserData w == workoutUserData workout
                    && workoutRevision w == WorkoutRevision 2
            Left _ -> False
        )
    ,
        ( "revision conflict prevents update"
        , case replaceObservation (WorkoutRevision 0) observation workout of
            Left (RevisionConflict _ _) -> True
            _ -> False
        )
    ,
        ( "invalid refresh rejected"
        , case replaceObservation
            (WorkoutRevision 1)
            (observation {observationRange = TimeRange start start, observationSport = Running emptyRunning})
            workout of
            Left (InvalidWorkout _) -> True
            _ -> False
        )
    ,
        ( "recalculation preserves reported values"
        , (recordedSummary <$> rideSummaries computedObservation) == Just rideSummary
        )
    ,
        ( "stale derived revision rejected"
        , invalidWorkout
            workout {workoutRevision = WorkoutRevision 2, workoutObservation = computedObservation}
        )
    ,
        ( "refresh invalidates cached results"
        , case replaceObservation (WorkoutRevision 1) computedObservation workout of
            Right w -> (calculatedSummary <$> rideSummaries (workoutObservation w)) == Just Nothing
            _ -> False
        )
    ,
        ( "user edit preserves imported observations except caches"
        , case replaceUserData (WorkoutRevision 1) emptyUserData workout of
            Right w -> workoutObservation w == observation && workoutUserData w == emptyUserData
            _ -> False
        )
    ]
  where
    withSport = withSportRange rideRange
    withSportRange r s = workout {workoutObservation = observation {observationRange = r, observationSport = s}}
    invalidWorkout = not . null . validateWorkout
    invalidCycling = invalidWorkout . withSport . Cycling
    outsideLap = Lap (TimeRange start (at 18000)) Nothing (reportedOnly emptyCyclingSummary) V.empty
    badMotion m = invalidCycling emptyCycling {cyclingMotion = m}
    badHeart xs = badMotion emptyMotion {motionHeartRate = V.fromList xs}
    rideSummaries o = case observationSport o of
        Cycling c -> Just (cyclingSummary c)
        Running _ -> Nothing
    computedObservation =
        observation
            { observationSport =
                Cycling
                    ride
                        { cyclingSummary =
                            Summaries
                                rideSummary
                                (Just (Calculated (WorkoutRevision 1) "config-1" "analysis-1" start emptyCyclingSummary))
                        }
            }
