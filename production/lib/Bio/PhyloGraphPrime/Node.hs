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
  , ResolutionCache
  , ResolutionInformation(..)
  , singletonNewickSerialization
  , singletonSubtreeLeafSet
  ) where


import Data.Bifunctor
import Data.BitVector
import Data.List.NonEmpty
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


instance Show s => Show (ResolutionInformation s) where

    show resInfo = unlines tokens
      where
        tokens =
          [ "Leaf Set  : " <> show (leafSetRepresentation resInfo)
          , "Subtree   : " <> show (subtreeRepresentation resInfo)
          , "Local Cost: " <> show (localSequenceCost     resInfo)
          , "Total Cost: " <> show (totalSubtreeCost      resInfo)
          , "Decoration: " <> show (characterSequence     resInfo)
          ]


instance Eq  (ResolutionInformation s) where

    lhs == rhs = leafSetRepresentation lhs == leafSetRepresentation rhs
              && subtreeRepresentation lhs == subtreeRepresentation rhs


instance Ord (ResolutionInformation s) where

    lhs `compare` rhs =
        case leafSetRepresentation lhs `compare` leafSetRepresentation lhs of
          EQ -> subtreeRepresentation lhs `compare` subtreeRepresentation rhs
          c  -> c


type ResolutionCache s = NonEmpty (ResolutionInformation s)


newtype NewickSerialization = NS String
  deriving (Eq, Ord)


newtype SubtreeLeafSet = LS BitVector
  deriving (Eq, Ord, Bits)


instance Semigroup SubtreeLeafSet where

    (<>) = (.|.)


instance Show SubtreeLeafSet where

    show (LS bv) = foldMap f $ toBits bv
      where
        f x = if x then "1" else "0"
    

instance Semigroup NewickSerialization where

    (NS lhs) <> (NS rhs) = NS $ "(" <> lhs <> "," <> rhs <> ")"


instance Show NewickSerialization where

    show (NS s) = s
    

instance Bifunctor PhylogeneticNode where

    bimap g f = 
      PNode <$> g . nodeDecorationDatum
            <*> f . sequenceDecoration


singletonNewickSerialization :: Int -> NewickSerialization
singletonNewickSerialization i = NS $ show i

singletonSubtreeLeafSet :: Int -> Int -> SubtreeLeafSet
singletonSubtreeLeafSet n i = LS . (`setBit` i) $ n `bitVec` (0 :: Integer)
