------------------------------------------------------------------------------
-- |
-- Module      :  Bio.PhyloGraphPrime.PhylogeneticDAG.Postorder
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Containing the master command for unifying all input types: tree, metadata, and sequence
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts #-}

module Bio.PhyloGraphPrime.PhylogeneticDAG.Postorder
  ( postorderSequence'
  ) where

import           Bio.PhyloGraphPrime.Node
import           Bio.PhyloGraphPrime.PhylogeneticDAG.Internal
import           Bio.PhyloGraphPrime.ReferenceDAG.Internal
import           Control.Arrow             ((&&&))
import           Control.Applicative       (liftA2)
import           Control.Monad.State.Lazy
import           Data.Foldable
import           Data.Hashable
import           Data.Hashable.Memoize
import qualified Data.IntMap        as IM
import           Data.Key
import qualified Data.Vector        as V
import           Prelude            hiding (zipWith)


-- |
-- Applies a traversal logic function over a 'ReferenceDAG' in a /pre-order/ manner.
--
-- The logic function takes a current node decoration,
-- a list of parent node decorations with the logic function already applied,
-- and returns the new decoration for the current node.
postorderSequence' :: (Eq z, Eq z', Hashable z, Hashable z')
                   => (u -> [u'] -> u')
                   -> (v -> [v'] -> v')
                   -> (w -> [w'] -> w')
                   -> (x -> [x'] -> x')
                   -> (y -> [y'] -> y')
                   -> (z -> [z'] -> z')
                   -> PhylogeneticDAG2 e n u  v  w  x  y  z
                   -> PhylogeneticDAG2 e n u' v' w' x' y' z'
postorderSequence' f1 f2 f3 f4 f5 f6 (PDAG2 dag) = PDAG2 $ newDAG dag
  where
    f6' = memoize2 f6
    newDAG        = RefDAG <$> const newReferences <*> rootRefs <*> graphData
    dagSize       = length $ references dag
    newReferences = V.generate dagSize h
      where
        h i = IndexData <$> const (memo ! i) <*> parentRefs <*> childRefs $ references dag ! i

--    memo :: Vector (PhylogeneticNode2 n (CharacterSequence u' v' w' x' y' z'))
    memo = V.generate dagSize h
      where
        h i =
          PNode2
              { resolutions          = liftA2 (generateLocalResolutions f1 f2 f3 f4 f5 f6') datumResolutions childResolutions
              , nodeDecorationDatum2 = nodeDecorationDatum2 $ nodeDecoration node
              }
          where
            node             = references dag ! i
            childIndices     = IM.keys $ childRefs node
            datumResolutions = resolutions $ nodeDecoration node
            
--            childResolutions :: NonEmpty [a]
            childResolutions = applySoftwireResolutions $ extractResolutionContext <$> childIndices
            extractResolutionContext = getResolutions &&& parentRefs . (references dag !)
            getResolutions j = fmap (addEdgeToEdgeSet (i,j)) . resolutions $ memo ! j
