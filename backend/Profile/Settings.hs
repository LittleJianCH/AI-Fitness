{-# LANGUAGE OverloadedStrings #-}

module Profile.Settings (emptySettings, validate, replace, profileAt) where

import Data.List (nub)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime)
import qualified Data.UUID.Types as UUID
import qualified Data.Vector as V
import Profile.Types

emptySettings :: UserSettings
emptySettings = UserSettings (SettingsRevision 0) (SoftwareSettings SystemAppearance) V.empty V.empty

validate :: UserSettings -> [Text]
validate settings
    | not (null limits) = limits
    | otherwise =
        ["bodyProfiles must have distinct non-nil IDs and increasing effective times" | not validHistory]
            <> [ "body parameters must be finite positive values; resting < threshold <= maximum heart rate"
               | not (all validBody profiles)
               ]
            <> [ "equipment must have distinct non-nil IDs, a name, and a finite positive optional mass"
               | not validEquipment
               ]
  where
    limits =
        ["bodyProfiles exceed the 1000-entry limit" | V.length (settingsBodyProfiles settings) > 1000]
            <> ["equipment exceeds the 200-entry limit" | V.length (settingsEquipment settings) > 200]
    profiles = V.toList (settingsBodyProfiles settings)
    equipment = V.toList (settingsEquipment settings)
    uniqueIds ids = UUID.nil `notElem` ids && length (nub ids) == length ids
    dates = map bodyEffectiveFrom profiles
    validHistory = uniqueIds (map bodyProfileId profiles) && and (zipWith (<) dates (drop 1 dates))
    validBody p =
        optionalPositive (bodyMassKilograms p)
            && optionalPositive (bodyHeightMetres p)
            && all validSport [bodyCycling p, bodyRunning p]
    validSport p = optionalPositive (sportThresholdWatts p) && maybe True validHeart (sportHeartRate p)
    validHeart p =
        all positive [heartRateResting p, heartRateMaximum p, heartRateThreshold p]
            && heartRateResting p < heartRateThreshold p
            && heartRateThreshold p <= heartRateMaximum p
            && positive ((heartRateThreshold p - heartRateResting p) / (heartRateMaximum p - heartRateResting p))
    validEquipment =
        uniqueIds (map equipmentId equipment)
            && all
                ( \e ->
                    let name = equipmentName e
                     in not (Text.null (Text.strip name))
                            && Text.length name <= 120
                            && not (Text.any (== '\0') name)
                            && optionalPositive (equipmentMassKilograms e)
                )
                equipment
    optionalPositive = maybe True positive
    positive x = x > 0 && not (isInfinite x || isNaN x)

-- The request carries the expected revision; only the server increments it.
replace :: UserSettings -> UserSettings -> Either [Text] UserSettings
replace current proposed
    | not (null validationErrors) = Left validationErrors
    | not (null errors) = Left errors
    | otherwise = Right proposed {settingsRevision = SettingsRevision (revision + 1)}
  where
    SettingsRevision revision = settingsRevision current
    history = settingsBodyProfiles current
    validationErrors = validate proposed
    errors =
        ["revision conflict" | settingsRevision current /= settingsRevision proposed]
            <> [ "existing body profile history is immutable"
               | V.take (V.length history) (settingsBodyProfiles proposed) /= history
               ]
            <> [ "retire equipment instead of removing its identity"
               | any missing (V.toList (settingsEquipment current))
               ]
    missing old =
        not
            ( V.any
                (\new -> equipmentId old == equipmentId new && equipmentKind old == equipmentKind new)
                (settingsEquipment proposed)
            )

profileAt :: UTCTime -> UserSettings -> Maybe BodyProfile
profileAt time =
    listToMaybe
        . reverse
        . V.toList
        . V.takeWhile ((<= time) . bodyEffectiveFrom)
        . settingsBodyProfiles
