module TestSuite.LibraryTests
  ( main
  , testSuite
  ) where

import Test.Tasty
import qualified Control.Evaluation.Test               as Evaluation
import qualified Text.Megaparsec.Custom.Test           as Megaparsec
import qualified File.Format.Fasta.Test                as Fasta
import qualified File.Format.Fastc.Test                as Fastc
import qualified File.Format.Newick.Test               as Newick
import qualified File.Format.TransitionCostMatrix.Test as TCM
import qualified File.Format.VertexEdgeRoot.Test       as VER
import qualified Analysis.Parsimony.Binary.Test        as Parsimony
--import qualified Analysis.DirectOptimization.Test      as DO
import qualified Bio.Phylogeny.Graph.Test              as Graph
import qualified File.Format.Conversion.Test           as Conversion

main :: IO ()
main = defaultMain testSuite

testSuite :: TestTree
testSuite = testGroup "Library Test Suite" 
  [ Evaluation.testSuite
  , Megaparsec.testSuite
  , Fasta.testSuite
  , Fastc.testSuite
  , Newick.testSuite
  , Conversion.testSuite
  , TCM.testSuite
  , VER.testSuite
  , Graph.testSuite
  -- , Parsimony.testSuite
  ]

