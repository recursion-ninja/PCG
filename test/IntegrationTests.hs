module Main
  ( main
  , testSuite
  ) where

import           Test.Tasty
import           Test.Tasty.Ingredients.Rerun (rerunningTests)
import qualified TestSuite.GoldenTests        as Golden (testSuite)
import qualified TestSuite.ScriptTests        as Script


main :: IO ()
main
  = testSuite >>=
    defaultMainWithIngredients
    [rerunningTests defaultIngredients]


testSuite :: IO TestTree
testSuite = testGroup "Integration Test Suite" . (\x -> scriptTests <> [x])
          <$> Golden.testSuite
  where
    scriptTests =
      [ Script.failureTestSuite
      , Script.commandTestSuite
      , Script.costTestSuite
      ]
