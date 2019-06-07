module Main (main) where

import           Data.Foldable
import qualified Benchmark.FASTA.Space as FASTA
import qualified Benchmark.FASTC.Space as FASTC
import           Weigh


main :: IO ()
main = mainWith $ do
    setColumns [Case, Allocated, GCs, Max]
    sequenceA_ $ mconcat
      [ FASTA.benchSpace
      , FASTC.benchSpace
      ]
