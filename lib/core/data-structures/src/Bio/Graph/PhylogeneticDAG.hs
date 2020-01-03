------------------------------------------------------------------------------
-- |
-- Module      :  Bio.PhyloGraphPrime.PhylogeneticDAG
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

module Bio.Graph.PhylogeneticDAG
  ( PhylogeneticFreeDAG(..)
  , PhylogeneticDAG(..)
  , PhylogeneticDAGish(..)
  , PostorderContextualData(..)
  , HasVirtualNodeMapping(..)
  , HasPhylogeneticForest(..)
  , HasColumnMetadata(..)
  , assignOptimalDynamicCharacterRootEdges
  , assignPunitiveNetworkEdgeCost
  , generateLocalResolutions
  , postorderSequence'
  , preorderFromRooting
  , preorderSequence
  , renderSummary
  , rootCosts
  , setEdgeSequences
  , getDotContextWithBaseAndIndex
  -- * Mapping over networks
  , edgePreorderMap
  , edgePostorderMap
  , edgePreorderFold
  , edgePostorderFold
  , nodePreorderMap
  , nodePostorderMap
  , nodePreorderFold
  , nodePostorderFold
  , setDefaultMetadata
  -- * Substitution functions
  , getNamedContext
  , substituteDAGs
  ) where


import           Bio.Graph.Node
import           Bio.Graph.PhylogeneticDAG.Class
import           Bio.Graph.PhylogeneticDAG.DynamicCharacterRerooting
import           Bio.Graph.PhylogeneticDAG.Internal
import           Bio.Graph.PhylogeneticDAG.NetworkEdgeQuantification
import           Bio.Graph.PhylogeneticDAG.Postorder
import           Bio.Graph.PhylogeneticDAG.Preorder
import           Bio.Graph.PhylogeneticDAG.Substitute
import           Bio.Graph.ReferenceDAG.Internal
import           Bio.Sequence
import           Data.Key
import           Data.List.NonEmpty                                  (NonEmpty)
import qualified Data.List.NonEmpty                                  as NE


-- |
-- Calculate the root cost for each character block.
rootCosts
  :: HasBlockCost u v w x y z
  => PhylogeneticDAG m s t u v w x y z -> NonEmpty Double
rootCosts (PDAG2 dag meta) = sequenceCost meta <$> rootDecs
  where
    roots     = rootRefs dag
    rootDecs  = characterSequence . NE.head . resolutions . nodeDecoration . (references dag !) <$> roots


-- |
-- Map over each node in a pre-order manner.
nodePreorderMap :: (n -> [n'] -> n')
nodePreorderMap = undefined


-- |
-- Map over each edge in a pre-order manner.
edgePreorderMap :: (e -> [e'] -> e')
edgePreorderMap = undefined


-- |
-- Map over each node in a post-order manner.
nodePostorderMap :: (n -> [n'] -> n')
nodePostorderMap = undefined


-- |
-- Map over each edge in a post-order manner.
edgePostorderMap :: (e -> [e'] -> e')
edgePostorderMap = undefined


-- |
-- Fold over each node in a pre-order manner.
nodePreorderFold :: (n -> [a] -> a)
nodePreorderFold = undefined


-- |
-- Fold over each edge in a pre-order manner.
edgePreorderFold :: (e -> [a] -> a)
edgePreorderFold = undefined


-- |
-- Fold over each node in a post-order manner.
nodePostorderFold :: (n -> [a] -> a)
nodePostorderFold = undefined


-- |
-- Fold over each edge in a pre-order manner.
edgePostorderFold :: (e -> [a] -> a)
edgePostorderFold = undefined