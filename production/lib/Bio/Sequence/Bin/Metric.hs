------------------------------------------------------------------------------
-- |
-- Module      :  Bio.Sequence.Bin.Metric
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE DeriveFunctor, FlexibleContexts #-}

module Bio.Sequence.Bin.Metric
  ( MetricBin(..)
  ) where


import Bio.Character.Static
import Bio.Sequence.SharedContinugousMetatdata
import Data.Monoid          (mappend)
import Data.Semigroup
import Data.TCM


-- |
-- A bin of one or more metric characters and thier corresponding metadata.
--
-- Use '(<>)' to construct larger bins with differing metadata.
--
-- There is currently no singleton-like constructor!
data MetricBin s
   = MetricBin
   { characterDecoration :: s
   , metatdataBounds     :: SharedMetatdataIntervals
   , tcmDefinition       :: TCM
   } deriving (Eq,Functor,Show)


instance EncodedAmbiguityGroupContainer (MetricBin s) where

    {-# INLINE symbolCount #-}
    symbolCount = size . tcmDefinition


instance Semigroup s => Semigroup (MetricBin s) where

  lhs <> rhs =
    MetricBin
      { characterDecoration = characterDecoration lhs    <>     characterDecoration rhs
      , metatdataBounds     = metatdataBounds     lhs `mappend` metatdataBounds     rhs
      , tcmDefinition       = tcmDefinition       lhs
      }
