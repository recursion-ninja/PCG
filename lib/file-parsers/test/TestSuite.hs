module Main
  ( main
  , testSuite
  ) where


import qualified File.Format.Fasta.Test                as Fasta
import qualified File.Format.Fastc.Test                as Fastc
import qualified File.Format.Newick.Test               as Newick
--import qualified File.Format.Nexus.Test                as Nexus
import qualified File.Format.TNT.Test                  as TNT
import qualified File.Format.TransitionCostMatrix.Test as TCM
import qualified File.Format.VertexEdgeRoot.Test       as VER
import           Test.Tasty
import           Test.Tasty.Ingredients.Rerun          (rerunningTests)
import qualified Text.Megaparsec.Custom.Test           as Megaparsec


main :: IO ()
main =
  defaultMainWithIngredients
  [ rerunningTests defaultIngredients ]
  testSuite


testSuite :: TestTree
testSuite = testGroup "Library Test Suite"
    [ Megaparsec.testSuite
    , Fasta.testSuite
    , Fastc.testSuite
    , Newick.testSuite
--    , Nexus.testSuite
    , TNT.testSuite
    , TCM.testSuite
    , VER.testSuite
    ]
