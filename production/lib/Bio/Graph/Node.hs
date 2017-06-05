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

module Bio.Graph.Node
  ( EdgeSet
  , NewickSerialization()
  , PhylogeneticNode (..)
  , PhylogeneticNode2(..)
  , ResolutionCache
  , ResolutionInformation(..)
  , SubtreeLeafSet()
  , addEdgeToEdgeSet
  , singletonEdgeSet
  , singletonNewickSerialization
  , singletonSubtreeLeafSet
  , pNode2
  ) where


import Data.Bifunctor
import Data.BitVector
import Data.EdgeSet
import Data.Foldable
import Data.List.NonEmpty (NonEmpty(..))
import Data.Semigroup


-- |
-- This serves as a computation /invariant/ node decoration designed to hold node
-- information such as name and later a subtree structure.
data  PhylogeneticNode n s
    = PNode
    { nodeDecorationDatum :: n
    , sequenceDecoration  :: s
    } deriving (Eq, Functor, Show)


-- |
-- This serves as a computation /dependant/ node decoration designed to hold node
-- information for a a phylogenetic network (or tree).
data  PhylogeneticNode2 s n
    = PNode2
    { resolutions          :: ResolutionCache s
    , nodeDecorationDatum2 :: n
    } deriving (Eq, Functor)


-- |
-- A safe constructor of a 'PhylogeneticNode2'.
pNode2 :: n -> ResolutionCache s -> PhylogeneticNode2 s n
pNode2 = flip PNode2


-- |
-- A collection of information used to memoize network optimizations.
data  ResolutionInformation s
    = ResInfo
    { totalSubtreeCost      :: Double
    , localSequenceCost     :: Double
    , leafSetRepresentation :: SubtreeLeafSet
    , subtreeRepresentation :: NewickSerialization
    , subtreeEdgeSet        :: EdgeSet (Int, Int)
    , characterSequence     :: s
    } deriving (Functor)


-- |
-- A collection of subtree resolutions. Represents a non-deterministic collection
-- of subtree choices.
type ResolutionCache s = NonEmpty (ResolutionInformation s)


-- |
-- A newick representation of a subtree. Semigroup instance used for subtree
-- joining.
newtype NewickSerialization = NS String
  deriving (Eq, Ord)


-- |
-- An arbitraryily ordered collection of leaf nodes in a subtree. Leaves in the
-- tree are uniquely identified by an index across the entire DAG. Set bits
-- represent a leaf uniquily identified by that index being present in the
-- subtree.
--
-- Use the 'Semigroup' operation '(<>)' to union the leaves included in a leaf
-- set.
newtype SubtreeLeafSet = LS BitVector
  deriving (Eq, Ord, Bits)


instance (Show n, Show s) => Show (PhylogeneticNode2 s n) where

    show node = unlines
        [ show $ nodeDecorationDatum2 node
        , "Resolutions: {" <> (show . length . resolutions) node <> "}\n"
        , unlines . fmap show . toList $ resolutions node
        ] 


instance Show s => Show (ResolutionInformation s) where

    show resInfo = unlines tokens
      where
        tokens =
           [ "Total Cost: "    <> show (totalSubtreeCost      resInfo)
           , "Local Cost: "    <> show (localSequenceCost     resInfo)
           , "Edge Set  : "    <> show (subtreeEdgeSet        resInfo)
           , "Leaf Set  : "    <> show (leafSetRepresentation resInfo)
           , "Subtree   : "    <> show (subtreeRepresentation resInfo)
           , "Decoration:\n\n" <> show (characterSequence     resInfo)
           ]


instance Eq  (ResolutionInformation s) where

    lhs == rhs = leafSetRepresentation lhs == leafSetRepresentation rhs
              && subtreeRepresentation lhs == subtreeRepresentation rhs


instance Ord (ResolutionInformation s) where

    lhs `compare` rhs =
        case leafSetRepresentation lhs `compare` leafSetRepresentation lhs of
          EQ -> subtreeRepresentation lhs `compare` subtreeRepresentation rhs
          c  -> c


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


-- |
-- Construct a singleton newick string with a unique identifier that can be
-- rendered to a string through it's 'Show' instance.
singletonNewickSerialization :: Show i => i -> NewickSerialization
singletonNewickSerialization i = NS $ show i


-- |
-- Construct a singleton leaf set by supplying the number of leaves and the
-- unique leaf index.
singletonSubtreeLeafSet :: Int -- ^ Leaf count
                        -> Int -- ^ Leaf index
                        -> SubtreeLeafSet
singletonSubtreeLeafSet n i = LS . (`setBit` i) $ n `bitVec` (0 :: Integer)


-- |
-- Adds an edge reference to an existing subtree resolution.
addEdgeToEdgeSet :: (Int, Int) -> ResolutionInformation s -> ResolutionInformation s
addEdgeToEdgeSet e r = r { subtreeEdgeSet = singletonEdgeSet e <> subtreeEdgeSet r }