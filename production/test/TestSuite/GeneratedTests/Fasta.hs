{-# LANGUAGE FlexibleContexts #-}

module TestSuite.GeneratedTests.Fasta 
  ( testSuite
  ) where

import Data.Either.Custom
import Data.Map                   (toList)
import File.Format.Fasta
import Test.Tasty                 (TestTree,testGroup)
import Test.Tasty.HUnit
import TestSuite.GeneratedTests.Internal
import Text.Parsec                (parse)

testSuite :: IO TestTree
testSuite = testGroup "fastaStreamParser" <$> sequence [validFastaFiles, invalidFastaFiles]

validFastaFiles :: IO TestTree
validFastaFiles = validateFileContents <$> validContents
  where
    validContents          = getFileContentsInDirectory "test/data-sets/fasta/valid"
    validateFileContents   = testGroup "Valid files" . fmap success . toList
    success (path,content) = testCase (show path) 
                           $ case result of
                               Left x  -> assertFailure $ show x
                               Right _ -> assert True
      where
       result = parse fastaStreamParser path content

invalidFastaFiles :: IO TestTree
invalidFastaFiles = validateFileContents <$> validContents
  where
    validContents          = getFileContentsInDirectory "test/data-sets/fasta/invalid"
    validateFileContents   = testGroup "Invalid files" . fmap failure . toList
    failure (path,content) = testCase (show path) . assert $ isLeft result
      where
        result = parse fastaStreamParser path content