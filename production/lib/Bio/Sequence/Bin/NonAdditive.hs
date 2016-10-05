------------------------------------------------------------------------------
-- |
-- Module      :  Bio.Sequence.Bin.NonAdditive
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts #-}

module Bio.Sequence.Bin.NonAdditive
  ( NonAdditiveBin(..)
  ) where


import Bio.Character.Static
import Bio.Sequence.SharedContinugousMetatdata
import Data.List.NonEmpty
import Data.Monoid          (mappend)
import Data.MonoTraversable (olength)
import Data.Semigroup


data NonAdditiveBin s
   = NonAdditiveBin
   { characterStream :: s
   , metatdataBounds :: SharedMetatdataIntervals
   } deriving (Eq,Show)


instance Semigroup s => Semigroup (NonAdditiveBin s) where

  lhs <> rhs =
    NonAdditiveBin
      { characterStream = characterStream lhs <> characterStream rhs
      , metatdataBounds = metatdataBounds lhs `mappend` metatdataBounds rhs
      }


nonAdditiveBin :: NonEmpty (NonEmpty String) -> GeneralCharacterMetadata -> NonAdditiveBin s
nonAdditiveBin staticCharacters corespondingMetadata =
  NonAdditiveBin
    { characterStream = newChars
    , metatdataBounds = singleton (olength newChars) corespondingMetadata
    }
  where
    newChars = encodeStream (characterAlphabet corespondingMetadata) staticCharacters

