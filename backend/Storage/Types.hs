module Storage.Types (Store, StorageError (..)) where

import Control.Monad.Trans.Except (ExceptT)
import Data.Text (Text)
import Hasql.Transaction (Transaction)
import Workout.Validation.Types (ValidationError)

type Store = ExceptT StorageError Transaction

-- Database errors deliberately carry no SQL parameters or stored payloads.
data StorageError
    = DatabaseFailure
    | UserConflict
    | SessionConflict
    | AuthenticationFailed
    | WorkoutConflict
    | SubmissionConflict
    | WorkoutNotManual
    | WorkoutNotFound
    | InvalidWorkout [ValidationError]
    | CorruptWorkout
    | ImportNotFound
    | ImportConflict
    | ImportReconciliationRequired
    | ImportRefreshRequired
    | ImportRetryRequired
    | InvalidImport
    | CorruptImport
    | ExportReceiptConflict
    | InvalidExportReceipt
    | CorruptExportReceipt
    | SettingsConflict
    | InvalidSettings [Text]
    | CorruptSettings
    | AnalysisTooLarge
    deriving (Eq, Show)
