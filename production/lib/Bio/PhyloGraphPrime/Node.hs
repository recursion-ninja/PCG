-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.PhyloGraphPrime.Node
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE DeriveFunctor, GeneralizedNewtypeDeriving #-}

module Bio.PhyloGraphPrime.Node
  ( PhylogeneticNode (..)
  , PhylogeneticNode2(..)
  , ResolutionInformation(..)
  ) where


import Data.Bifunctor
import Data.BitVector
import Data.DuplicateSet
import Data.Semigroup


-- |
-- This serves as a computation /invariant/ node decoration designed to hold node
-- information such as name and later a subtree structure.
data  PhylogeneticNode n s
    = PNode
    { nodeDecorationDatum :: n
    , sequenceDecoration  :: s
    } deriving (Eq, Functor)



-- |
-- This serves as a computation /dependant/ node decoration designed to hold node
-- information for a a phylogenetic network (or tree).
data  PhylogeneticNode2 s n
    = PNode2
    { resolutions          :: ResolutionCache s
    , nodeDecorationDatum2 :: n
    } deriving (Eq, Functor)


-- | A collection of information used to memoize network optimizations.
data  ResolutionInformation s
    = ResInfo
    { leafSetRepresentation :: SubtreeLeafSet
    , subtreeRepresentation :: NewickSerialization
    , characterSequence     :: s
    , localSequenceCost     :: Double
    , totalSubtreeCost      :: Double 
    } deriving (Functor)


instance Eq  (ResolutionInformation s) where

    lhs == rhs = leafSetRepresentation lhs == leafSetRepresentation rhs
              && subtreeRepresentation lhs == subtreeRepresentation rhs


instance Ord (ResolutionInformation s) where

    lhs `compare` rhs =
        case leafSetRepresentation lhs `compare` leafSetRepresentation lhs of
          EQ -> subtreeRepresentation lhs `compare` subtreeRepresentation rhs
          c  -> c


type ResolutionCache s = DuplicateSet (ResolutionInformation s)


newtype NewickSerialization = NS String
  deriving (Eq, Ord, Semigroup)


newtype SubtreeLeafSet = LS BitVector
  deriving (Eq, Ord, Bits)


instance Semigroup SubtreeLeafSet where

    (<>) =  (.|.)
    

instance Bifunctor PhylogeneticNode where

    bimap g f = 
      PNode <$> g . nodeDecorationDatum
            <*> f . sequenceDecoration
