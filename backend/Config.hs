module Config (config) where

import IHP.FrameworkConfig (ConfigBuilder)

-- IHP reads PORT and IHP_ENV and supplies the remaining defaults.
config :: ConfigBuilder
config = pure ()
