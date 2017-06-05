-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Character.Decoration.Metric
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

module Bio.Character.Decoration.Metric
  ( MetricDecorationInitial()
  , MetricCharacterDecoration()
  , SankoffOptimizationDecoration()
  , SankoffDecoration()
  , StateContributionList
  , DiscreteExtensionSankoffDecoration(..)
  , GeneralCharacterMetadata()
  , DiscreteCharacterMetadata()
  , DiscreteCharacterDecoration()
  , HasCharacterAlphabet(..)
  , HasCharacterCost(..)
  , HasCharacterCostVector(..)
  , HasCharacterName(..)
  , HasCharacterWeight(..)
  , HasStateMinTuple(..)
  , HasDiscreteCharacter(..)
  , HasSymbolChangeMatrix(..)
  , HasTransitionCostMatrix(..)
  , HasIsLeaf(..)
  ) where

import Bio.Character.Decoration.Discrete
import Bio.Character.Decoration.Metric.Class
import Bio.Character.Decoration.Metric.Internal
import Bio.Character.Decoration.Shared
