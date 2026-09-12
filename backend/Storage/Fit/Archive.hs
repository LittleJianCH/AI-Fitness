{-# LANGUAGE PackageImports #-}

module Storage.Fit.Archive (digest, retain) where

import Control.Exception (IOException, bracket, bracketOnError, catch)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as Text
import Data.UUID.Types (UUID)
import qualified Data.UUID.Types as UUID
import System.Directory (makeAbsolute, removeFile, renameFile)
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose, hFlush, openBinaryTempFile)
import System.IO.Error (isAlreadyExistsError, isDoesNotExistError)
import qualified System.Posix.Directory as Directory
import System.Posix.Files (setFileMode)
import System.Posix.IO (OpenMode (ReadOnly), closeFd, defaultFileFlags, handleToFd, openFd)
import System.Posix.Unistd (fileSynchronise)
import "crypton" Crypto.Hash (Digest, SHA256, hash)

digest :: BS.ByteString -> Text
digest bytes = Text.pack (show (hash bytes :: Digest SHA256))

-- Client filenames never enter a storage path. Temp files are private and on
-- the same filesystem. Sync before rename and publication; a crash before the
-- database commit can leave an unreferenced archive, never a partial published file.
retain :: FilePath -> UUID -> BS.ByteString -> IO ()
retain configuredRoot owner bytes = do
    root <- makeAbsolute configuredRoot
    let directory = root </> UUID.toString owner
        destination = directory </> Text.unpack (digest bytes) <> ".fit"
    ensureDirectory directory
    setFileMode root 0o700
    setFileMode directory 0o700
    bracketOnError (openBinaryTempFile directory ".upload-") cleanup $ \(path, handle) -> do
        BS.hPut handle bytes
        hFlush handle
        bracket (handleToFd handle) closeFd fileSynchronise
        renameFile path destination
        syncDirectory directory
        syncDirectory root
  where
    syncDirectory path = bracket (openFd path ReadOnly defaultFileFlags) closeFd fileSynchronise
    cleanup (path, handle) = do
        hClose handle `catch` ignoreClosed
        removeFile path `catch` ignoreMissing
    ignoreClosed :: IOException -> IO ()
    ignoreClosed _ = pure ()
    ignoreMissing :: IOException -> IO ()
    ignoreMissing e = if isDoesNotExistError e then pure () else ioError e

-- Sync each newly created directory entry, including a new configured root.
-- Repeating creation is safe when two first uploads arrive together.
ensureDirectory :: FilePath -> IO ()
ensureDirectory path
    | takeDirectory path == path = pure ()
    | otherwise = do
        ensureDirectory (takeDirectory path)
        Directory.createDirectory path 0o700 `catch` alreadyExists
        bracket (openFd (takeDirectory path) ReadOnly defaultFileFlags) closeFd fileSynchronise
  where
    alreadyExists :: IOException -> IO ()
    alreadyExists e = if isAlreadyExistsError e then pure () else ioError e
