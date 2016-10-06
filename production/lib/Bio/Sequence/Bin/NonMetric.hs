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

{-# LANGUAGE FlexibleContexts #-}

module Bio.Sequence.Bin.NonMetric
  ( NonMetricBin(..)
  ) where


import Bio.Character.Static
import Bio.Sequence.SharedContinugousMetatdata
import Data.List.NonEmpty
import Data.Monoid          (mappend)
import Data.Semigroup
import Data.TCM (TCM)


data NonMetricBin s
   = NonMetricBin
   { characterDecoration :: s
   , tcmDefinition       :: TCM
   , metatdataBounds     :: SharedMetatdataIntervals
   } deriving (Eq,Show)


instance Semigroup s => Semigroup (NonMetricBin s) where

  lhs <> rhs =
    NonMetricBin
      { characterDecoration = characterDecoration lhs    <>     characterDecoration rhs
      , tcmDefinition       = tcmDefinition       lhs
      , metatdataBounds     = metatdataBounds     lhs `mappend` metatdataBounds     rhs
      }
