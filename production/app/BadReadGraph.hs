module BadReadGraph where

import Analysis.GenericFitch
import Bio.Phylogeny.Graph
import Bio.Phylogeny.Graph.Utilities
import Bio.Phylogeny.Graph.Output
import Bio.Phylogeny.Tree.Node
import Control.Monad                (sequence_, liftM2)
import Data.Functor                 ((<$))
import Data.Vector                  (singleton)
import qualified Data.IntMap as IM
import qualified Data.Vector as V
import File.Format.Fasta
import qualified File.Format.Newick as N
import File.Format.Newick.Converter
import Text.Megaparsec

badReadGraph :: FilePath -> FilePath -> IO DAG
badReadGraph fastaPath newickPath = do
  fastaResult  <- parse (fastaStreamConverter DNA =<< fastaStreamParser)  fastaPath  <$> readFile fastaPath
  newickResult <- parse N.newickStreamParser newickPath <$> readFile newickPath
  case (fastaResult, newickResult) of
    (Left  x, Left  y) -> mempty <$ sequence_ (putStrLn <$> [show x, show y])
    (Left  x, _      ) -> mempty <$ putStrLn (show x)
    (_      , Left  y) -> mempty <$ putStrLn (show y)
    (Right x, Right y) -> pure $ convertBoth (head y) (coerceFasta x)
  where
    coerceFasta = fmap (singleton . Just)

madRead = badReadGraph "../../TestDat/fakeArtmor.fas" "../../TestDat/artmor.tre"
--badNodes = (V.filter (\n -> isLeaf n && null (encoded n))) <$> (nodes <$> madRead)
--badNames = (V.map (\n -> (IM.! (code n)) <$> (nodeNames <$> madRead))) <$> badNodes
madness = rootCost . allOptimization 1 <$> madRead
outputMad = outPutDot "TestArtmor.dot" =<< ((Graph . pure) <$> madRead) 
checkOuts = liftM2 (V.zipWith (\n e -> not (isLeaf n) && null (outNodes e))) (nodes <$> madRead) (edges <$> madRead)
