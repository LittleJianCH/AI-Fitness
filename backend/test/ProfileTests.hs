{-# LANGUAGE OverloadedStrings #-}

module ProfileTests (cases) where

import Data.Either (isLeft)
import Data.Maybe (fromMaybe, isNothing)
import qualified Data.UUID.Types as UUID
import qualified Data.Vector as V
import qualified Fixtures as F
import Profile.Settings
import Profile.Types

cases :: [(String, Bool)]
cases =
    [
        ( "settings: empty settings contain no invented body values"
        , null (validate emptySettings) && isNothing (profileAt F.start emptySettings)
        )
    , ("settings: effective boundary is inclusive", profileAt F.start initial == Just first)
    ,
        ( "settings: oversized profiles rejected without inspecting entries"
        , let oversized = emptySettings {settingsBodyProfiles = V.replicate 1001 (error "oversized entries evaluated")}
           in validate oversized == ["bodyProfiles exceed the 1000-entry limit"]
                && replace emptySettings oversized == Left ["bodyProfiles exceed the 1000-entry limit"]
        )
    ,
        ( "settings: oversized equipment rejected without inspecting entries"
        , let oversized = equipped {settingsEquipment = V.replicate 201 (error "oversized entries evaluated")}
           in validate oversized == ["equipment exceeds the 200-entry limit"]
                && replace equipped oversized == Left ["equipment exceeds the 200-entry limit"]
        )
    ,
        ( "settings: later profile is not applied to earlier workouts"
        , profileAt (F.at 30) history == Just first
        )
    , ("settings: effective boundary selects new parameters", profileAt (F.at 60) history == Just second)
    , ("settings: no backward extrapolation", isNothing (profileAt (F.at (-1)) initial))
    ,
        ( "settings: revisions advance only at successful replacement"
        , fmap settingsRevision (replace emptySettings initial) == Right (SettingsRevision 1)
        )
    ,
        ( "settings: stale replacement is rejected"
        , isLeft (replace (initial {settingsRevision = SettingsRevision 1}) initial)
        )
    ,
        ( "settings: historical body entries cannot silently change"
        , isLeft
            (replace initial (initial {settingsBodyProfiles = V.singleton (first {bodyMassKilograms = Just 90})}))
        )
    , ("settings: historical entries cannot disappear", isLeft (replace initial emptySettings))
    ,
        ( "settings: duplicate profile IDs rejected"
        , not
            ( null
                (validate (initial {settingsBodyProfiles = V.fromList [first, first {bodyEffectiveFrom = F.at 60}]}))
            )
        )
    ,
        ( "settings: non-finite body values rejected"
        , not
            ( null
                (validate (initial {settingsBodyProfiles = V.singleton (first {bodyMassKilograms = Just (1 / 0)})}))
            )
        )
    ,
        ( "settings: threshold must be above resting HR"
        , not
            ( null
                ( validate
                    ( initial
                        { settingsBodyProfiles =
                            V.singleton
                                (first {bodyCycling = SportProfile Nothing (Just (HeartRateProfile 60 180 60 Exponent192))})
                        }
                    )
                )
            )
        )
    , ("settings: retirement preserves equipment identity", isLeft (replace equipped emptySettings))
    ,
        ( "settings: equipment names reject database-invalid characters"
        , not
            (null (validate (equipped {settingsEquipment = V.singleton (bike {equipmentName = "bad\0name"})})))
        )
    ]
  where
    first =
        BodyProfile
            (uuid "00000000-0000-0000-0000-000000000001")
            F.start
            (Just 70)
            Nothing
            (SportProfile (Just 200) Nothing)
            (SportProfile Nothing Nothing)
    second =
        first
            { bodyProfileId = uuid "00000000-0000-0000-0000-000000000002"
            , bodyEffectiveFrom = F.at 60
            , bodyMassKilograms = Just 80
            }
    initial = emptySettings {settingsBodyProfiles = V.singleton first}
    history = initial {settingsBodyProfiles = V.fromList [first, second]}
    bike =
        Equipment (uuid "00000000-0000-0000-0000-000000000003") Bicycle "Synthetic bicycle" (Just 8) False
    equipped = emptySettings {settingsEquipment = V.singleton bike}
    uuid = fromMaybe (error "Invalid synthetic UUID") . UUID.fromString
