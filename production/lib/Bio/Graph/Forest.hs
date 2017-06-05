-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Graph.Forest
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- The Phylogentic Graph types.
--
-- 
--
-----------------------------------------------------------------------------

{-# LANGUAGE DeriveTraversable, GeneralizedNewtypeDeriving, TypeFamilies #-}

module Bio.Graph.Forest
  ( PhylogeneticForest(..)
  ) where

import Data.Key
import Data.List.NonEmpty            (NonEmpty)
import Data.Maybe
import Data.Semigroup
import Data.Semigroup.Foldable
import Data.Semigroup.Traversable
import Prelude                hiding (lookup)


-- |
-- A newtype wrapper for a 'NonEmpty' collection of forests.
newtype PhylogeneticForest a
      = PhylogeneticForest (NonEmpty a)
      deriving (Foldable, Foldable1, Functor, Semigroup, Traversable)


type instance Key PhylogeneticForest = Int


instance Adjustable PhylogeneticForest where

    {-# INLINE adjust  #-}
    adjust  f i = PhylogeneticForest . adjust  f i . unwrap

    {-# INLINE replace #-}
    replace i e = PhylogeneticForest . replace i e . unwrap


instance FoldableWithKey PhylogeneticForest where

    {-# INLINE toKeyedList #-}
    toKeyedList = toKeyedList . unwrap

    {-# INLINE foldMapWithKey #-}
    foldMapWithKey f   = foldMapWithKey f   . unwrap

    {-# INLINE foldrWithKey #-}
    foldrWithKey   f e = foldrWithKey   f e . unwrap

    {-# INLINE foldlWithKey #-}
    foldlWithKey   f e = foldlWithKey   f e . unwrap


instance FoldableWithKey1 PhylogeneticForest where

    {-# INLINE foldMapWithKey1 #-}
    foldMapWithKey1 f = foldMapWithKey1 f . unwrap


instance Indexable PhylogeneticForest where

    {-# INLINE index #-}
    index forest i = fromMaybe errorMessage $ i `lookup` unwrap forest
      where
        errorMessage =  error $ mconcat
            [ "Could not index PhylogeneticForest at location '"
            , show i
            , "' with a valid range of [0,"
            , show $ length forest
            , "]."
            ]


instance Keyed PhylogeneticForest where

    {-# INLINE mapWithKey #-}
    mapWithKey f = PhylogeneticForest . mapWithKey f . unwrap


instance Lookup PhylogeneticForest where

    {-# INLINE lookup #-}
    lookup i = lookup i . unwrap


instance Traversable1 PhylogeneticForest where

    {-# INLINE traverse1 #-}
    traverse1 f = fmap PhylogeneticForest . traverse1 f . unwrap


instance TraversableWithKey PhylogeneticForest where

    {-# INLINE traverseWithKey #-}
    traverseWithKey  f = fmap PhylogeneticForest . traverseWithKey f . unwrap

    {-# INLINE mapWithKeyM #-}
    mapWithKeyM      f = fmap PhylogeneticForest . mapWithKeyM     f . unwrap


instance TraversableWithKey1 PhylogeneticForest where

    {-# INLINE traverseWithKey1 #-}
    traverseWithKey1 f = fmap PhylogeneticForest . traverseWithKey1 f . unwrap


{-# INLINE unwrap #-}
unwrap :: PhylogeneticForest a -> NonEmpty a
unwrap (PhylogeneticForest x) = x

