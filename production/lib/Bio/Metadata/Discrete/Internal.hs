-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Metadata.Discrete.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts, FlexibleInstances, MultiParamTypeClasses #-}

module Bio.Metadata.Discrete.Internal
  ( DiscreteCharacterMetadataDec()
  , DiscreteCharacterMetadata(..)
  , GeneralCharacterMetadata(..)
  , HasCharacterAlphabet(..)
  , HasCharacterName(..)
  , HasCharacterWeight(..)
  , discreteMetadata
  ) where


import Bio.Metadata.CharacterName
import Bio.Metadata.Discrete.Class
import Bio.Metadata.General
import Control.Lens
import Data.Alphabet
import Data.List (intercalate)
import Data.Monoid


-- |
-- Represents a concrete type containing metadata fields shared across all
-- discrete different bins. Continous bins do not have Alphabets.
data DiscreteCharacterMetadataDec
   = DiscreteCharacterMetadataDec
   { alphabet       :: Alphabet String
   , generalData    :: GeneralCharacterMetadataDec
   }


-- |
-- A decoration of an initial encoding of a dynamic character which has the
-- appropriate 'Lens' & character class constraints.
class ( GeneralCharacterMetadata s
      , HasCharacterAlphabet     s (Alphabet String)
      ) => DiscreteCharacterMetadata s where

    extractDiscreteCharacterMetadata :: s -> DiscreteCharacterMetadataDec


instance Eq DiscreteCharacterMetadataDec where

    lhs == rhs = alphabet    lhs == alphabet       rhs
              && generalData lhs == generalData    rhs


instance Show DiscreteCharacterMetadataDec where

    show e = intercalate "\n"
      [ "DiscreteCharacterMetadata"
      , "  CharacterName: " <> show (e ^. characterName    )
      , "  Alphabet:      " <> show (e ^. characterAlphabet)
      , "  Weight:        " <> show (e ^. characterWeight  )
      ]



-- | (✔)
instance GeneralCharacterMetadata DiscreteCharacterMetadataDec where

    {-# INLINE extractGeneralCharacterMetadata #-}
    extractGeneralCharacterMetadata = generalData


-- | (✔)
instance DiscreteCharacterMetadata DiscreteCharacterMetadataDec where

    {-# INLINE extractDiscreteCharacterMetadata #-}
    extractDiscreteCharacterMetadata = id


-- | (✔)
instance HasCharacterAlphabet DiscreteCharacterMetadataDec (Alphabet String) where

    characterAlphabet = lens alphabet $ \e x -> e { alphabet = x }


-- | (✔)
instance HasCharacterName DiscreteCharacterMetadataDec CharacterName where

    characterName = lens (\e -> generalData e ^. characterName)
                  $ \e x -> e { generalData = generalData e & characterName .~ x }


-- | (✔)
instance HasCharacterWeight DiscreteCharacterMetadataDec Double where

    characterWeight = lens (\e -> generalData e ^. characterWeight)
                    $ \e x -> e { generalData = generalData e & characterWeight .~ x }


-- |
-- Construct a concrete typed 'DiscreteCharacterMetadataDec' value from the supplied inputs.
discreteMetadata :: CharacterName -> Double -> Alphabet String -> DiscreteCharacterMetadataDec
discreteMetadata name weight alpha =
    DiscreteCharacterMetadataDec
    { alphabet       = alpha
    , generalData    = generalMetadata name weight
    }