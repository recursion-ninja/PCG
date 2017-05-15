------------------------------------------------------------------------------
-- |
-- Module      :  Bio.Metadata.Sequence.Block.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts, FlexibleInstances, MultiParamTypeClasses #-}

module Bio.Sequence.Block.Internal
  ( CharacterBlock(..)
  ) where


import Data.Foldable
import Data.Semigroup
import Data.Vector           (Vector)
import Data.Vector.Instances ()
import Prelude        hiding (zipWith)


-- |
-- Represents a block of charcters which are optimized atomically together across
-- networks. The 'CharacterBlock' is polymorphic over static and dynamic character
-- definitions.
--
-- Use '(<>)' to construct larger blocks.
data CharacterBlock u v w x y z
   = CharacterBlock
   { continuousCharacterBins  :: Vector u
   , nonAdditiveCharacterBins :: Vector v
   , additiveCharacterBins    :: Vector w
   , metricCharacterBins      :: Vector x
   , nonMetricCharacterBins   :: Vector y
   , dynamicCharacters        :: Vector z
   } deriving (Eq)


instance Semigroup (CharacterBlock u v w x y z) where

    lhs <> rhs =
        CharacterBlock
          { continuousCharacterBins  = continuousCharacterBins  lhs <> continuousCharacterBins  rhs
          , nonAdditiveCharacterBins = nonAdditiveCharacterBins lhs <> nonAdditiveCharacterBins rhs
          , additiveCharacterBins    = additiveCharacterBins    lhs <> additiveCharacterBins    rhs
          , metricCharacterBins      = metricCharacterBins      lhs <> metricCharacterBins      rhs
          , nonMetricCharacterBins   = nonMetricCharacterBins   lhs <> nonMetricCharacterBins   rhs
          , dynamicCharacters        = dynamicCharacters        lhs <> dynamicCharacters        rhs
          }


instance ( Show u
         , Show v
         , Show w
         , Show x
         , Show y
         , Show z
         ) => Show (CharacterBlock u v w x y z) where

    show block = unlines
        [ "Fitch Characters:"
        , niceRendering $ nonAdditiveCharacterBins block
        , "Additive Characters:"
        , niceRendering $ additiveCharacterBins block
        , "NonMetric Characters:"
        , niceRendering $ nonMetricCharacterBins block
        , "Continuous Characters: "
        , niceRendering $ continuousCharacterBins block
        , "Metric Characters:"
        , niceRendering $ metricCharacterBins block
        , "Dynamic Characters:"
        , niceRendering $ dynamicCharacters block
        ]
      where
        niceRendering :: (Foldable t, Show a) => t a -> String
        niceRendering = unlines . fmap (unlines . fmap ("  " <>) . lines . show) . toList

