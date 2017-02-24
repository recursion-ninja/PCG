-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Character.Decoration.Dynamic
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

module Bio.Character.Decoration.Dynamic
  ( DynamicDecorationInitial()
  , DirectOptimizationPostOrderDecoration()
  , DynamicDecorationDirectOptimization()
  , DynamicDecorationImpliedAlignment()
  , SimpleDynamicDecoration()
  , DirectOptimizationDecoration()
  , ImpliedAlignmentDecoration()
  , DynamicCharacterDecoration(..)
  , DynamicDecorationDirectOptimizationPostOrderResult()
  , GeneralCharacterMetadata()
  , DiscreteCharacterMetadata()
  , DiscreteWithTcmCharacterMetadata()
  , DynamicCharacterMetadata()
  , SimpleDynamicExtensionPostOrderDecoration(..)
  , PostOrderExtensionDirectOptimizationDecoration(..)
  , HasCharacterAlphabet(..)
  , HasCharacterCost(..)
  , HasCharacterName(..)
  , HasCharacterWeight(..)
  , HasEncoded(..)
  , HasFinalGapped(..)
  , HasFinalUngapped(..)
  , HasPreliminaryGapped(..)
  , HasPreliminaryUngapped(..)
  , HasLeftAlignment(..)
  , HasRightAlignment(..)
  , HasImpliedAlignment(..)
  , HasSymbolChangeMatrix(..)
  , HasTransitionCostMatrix(..)
  , HasSparseTransitionCostMatrix(..)
  , HasDenseTransitionCostMatrix(..)
  , PossiblyMissingCharacter(..)
  ) where

import Bio.Character.Decoration.Dynamic.Class
import Bio.Character.Decoration.Dynamic.Internal
import Bio.Character.Decoration.Shared
import Bio.Character.Encodable
import Bio.Metadata.Discrete
import Bio.Metadata.DiscreteWithTCM
import Bio.Metadata.Dynamic
import Bio.Metadata.General

