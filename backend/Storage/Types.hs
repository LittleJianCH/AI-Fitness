module Storage.Types (Store, StorageError (..)) where

import Control.Monad.Trans.Except (ExceptT)
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
    deriving (Eq, Show)
