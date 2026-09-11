module Workout.Sport (motion, heartRate, power, speed, altitude, position, invalidateCalculated) where

import qualified Workout.Cycling.Update as Cycling
import Workout.Measurement.Types
import qualified Workout.Running.Update as Running
import Workout.Sport.Types

motion :: Sport -> MotionData
motion sport = case sport of
    Cycling dat -> cyclingMotion dat
    Running dat -> runningMotion dat

heartRate :: Sport -> TimeSeries HeartRate
heartRate = motionHeartRate . motion

power :: Sport -> TimeSeries Power
power = motionPower . motion

speed :: Sport -> TimeSeries Speed
speed = motionSpeed . motion

altitude :: Sport -> TimeSeries Altitude
altitude = motionAltitude . motion

position :: Sport -> TimeSeries Position
position = motionPosition . motion

invalidateCalculated :: Sport -> Sport
invalidateCalculated sport = case sport of
    Cycling dat -> Cycling (Cycling.invalidateCalculated dat)
    Running dat -> Running (Running.invalidateCalculated dat)
