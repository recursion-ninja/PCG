{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Strict            #-}

module TestSuite.GoldenTests
  ( testSuite
  ) where

import Control.DeepSeq
import Control.Monad         (filterM, void)
import Data.Text             (pack)
import Data.Tree             (flatten, unfoldTreeM)
import System.Directory
import System.FilePath.Posix
import Test.Tasty
import Test.Tasty.Golden
import Turtle                (cd, decodeString, encodeString, pwd, shellStrict)

import Debug.Trace

type Extension = String

testSuite :: IO TestTree
testSuite = do
    pcgFiles <- getPCGFiles goldenDir
    let extensions = ["data", "dot", "xml"]
    let testInputs = [(pcg, ext) | pcg <- pcgFiles, ext <- extensions]
    tests <- traverse goldenTest testInputs
    pure $ testGroup "Golden Test Suite:" tests

-- |
-- Runs a pcg file [file-name].pcg producing [file-name].extension for a
-- given extension which is then compared to [file-name]_extension.golden. If the
-- golden file does not exist the test will generate it.

goldenTest :: (FilePath, Extension) -> IO TestTree
goldenTest (filePath, extension) = do
  let testName = filePath
  let outputFilePath = filePath -<.> extension
  let goldenFilePath = makeGolden filePath
  pure  $
    goldenVsFile
      testName
      goldenFilePath
      outputFilePath
      (generateOutput filePath)
  where
    makeGolden :: FilePath -> FilePath -- Generates a name for the golden file
    makeGolden = (<.> "golden") . (<> "_" <> extension) . dropExtension

-- |
-- Runs pcg on the file passed in.
generateOutput :: FilePath -> IO ()
generateOutput fp
  = do
  baseDir <- getCurrentDirectory
  setCurrentDirectory fileDir   -- Change to filepath directory.
  _ <- shellRunner $ mconcat
          [ "stack exec pcg -- --input "
          , fileName
          , " --output "
          , testLog
          ]                    -- Run pcg on file passing StdOut to log file.
  setCurrentDirectory baseDir  -- Return to base directory

  where
    (fileDir, fileName) = splitFileName fp
    shellRunner = void . (`shellStrict` mempty) . pack



-- |
-- Recursively gets all .pcg files in a directory.
getPCGFiles :: FilePath -> IO [FilePath]
getPCGFiles fp = do
  baseDir  <- getCurrentDirectory
  subDirs  <- getSubDirs fp
  relPaths <- concat <$> traverse getPCGFilesInDir subDirs
  pure $ (baseDir </>) <$> relPaths

    where
      getPCGFilesInDir :: FilePath -> IO [FilePath]
      getPCGFilesInDir =
        let filterPCG = filter $ (== ".pcg") . takeExtension
        in  (filterPCG <$>) . listDirectoryWithFilePath

      getSubDirs :: FilePath -> IO [FilePath] -- Get all subdirectories recursively
      getSubDirs path = do
        dirTree <- unfoldTreeM listTopDirs path
        let dirList = flatten dirTree
        pure dirList

        where
          listTopDirs :: FilePath -> IO (FilePath, [FilePath])
          listTopDirs x = do
            topDirs <- (filterM doesDirectoryExist =<<)
                     . listDirectoryWithFilePath $ x
            pure (x, topDirs)


-- |
-- Takes a directory filepath and returns a list of all files within
-- the directory with full filepaths.
listDirectoryWithFilePath :: FilePath -> IO [FilePath]
listDirectoryWithFilePath fp
  = (fmap (fp </>) <$>)
  . listDirectory
  $ fp


-- |
-- Name of test log file.
testLog :: FilePath
testLog = "test" <.> "log"

-- |
-- Name of golden tests directory.
goldenDir :: FilePath
goldenDir = "datasets" </> "golden-tests"
