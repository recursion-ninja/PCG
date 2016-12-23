-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Character.Decoration.Discrete
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts, FlexibleInstances, FunctionalDependencies, MultiParamTypeClasses #-}

-- For derived instance of PossiblyMissingCharacter
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Bio.Character.Decoration.Discrete
  ( DiscreteDecoration()
  , DiscreteCharacterDecoration()
  , DiscreteCharacterMetadata()
  , GeneralCharacterMetadata()
  , HasCharacterAlphabet(..)
  , HasCharacterName(..)
  , HasCharacterSymbolTransitionCostMatrixGenerator(..)
  , HasCharacterTransitionCostMatrix(..)
  , HasCharacterWeight(..)
  , HasDiscreteCharacter(..)
  , PossiblyMissingCharacter(..)
  , SimpleDiscreteCharacterDecoration(..)
  , showDiscreteCharacterElement
  ) where


import Bio.Character.Encodable
import Bio.Metadata.Discrete
import Bio.Metadata.CharacterName
import Control.Lens
import Data.Alphabet
import Data.TCM


-- |
-- General, concrete type for Discrete characters.
data DiscreteDecoration c
   = DiscreteDec
   { discreteDecorationCharacter :: c
   , metadata                    :: DiscreteCharacterMetadataDec c
   }


instance EncodableStreamElement c => Show (DiscreteDecoration c) where

    show = showDiscreteCharacterElement


-- |
-- Show an appropriate instance of 'HasDiscreteCharacter' that is also
-- 'HasCharacterAlphabet' by decoding the 'EncodableStreamElement' over the 'Alphabet';
-- both of which contained in the lensed type.
showDiscreteCharacterElement :: ( EncodableStreamElement a
                                , HasCharacterAlphabet s (Alphabet String)
                                , HasDiscreteCharacter s a
                                ) => s -> String
showDiscreteCharacterElement = showStreamElement <$> (^. characterAlphabet) <*> (^. discreteCharacter)


-- | (✔)
instance PossiblyMissingCharacter c => PossiblyMissingCharacter (DiscreteDecoration c) where

    isMissing = isMissing . (^. discreteCharacter)

    toMissing x = x & discreteCharacter %~ toMissing


-- |
-- A 'Lens' for the 'discreteCharacter' field
class HasDiscreteCharacter s a | s -> a where

    discreteCharacter :: Lens' s a
    {-# MINIMAL discreteCharacter #-}


-- | (✔)
class ( HasDiscreteCharacter s a
      , EncodableStaticCharacter a
      , DiscreteCharacterMetadata s a
      ) => DiscreteCharacterDecoration s a | s -> a where


-- | (✔)
class DiscreteCharacterDecoration s a => SimpleDiscreteCharacterDecoration s a | s -> a where

    toDiscreteCharacterDecoration :: CharacterName -> Double -> Alphabet String -> TCM -> (x -> a) -> x -> s
    {-# MINIMAL toDiscreteCharacterDecoration #-}



-- | (✔)
instance HasDiscreteCharacter (DiscreteDecoration c) c where

    discreteCharacter = lens discreteDecorationCharacter (\e x -> e { discreteDecorationCharacter = x })


-- | (✔)
instance HasCharacterAlphabet (DiscreteDecoration c) (Alphabet String) where

    characterAlphabet = lens getter setter
      where
         getter e   = metadata e ^. characterAlphabet
         setter e x = e { metadata = metadata e &  characterAlphabet .~ x }


-- | (✔)
instance HasCharacterName (DiscreteDecoration c) CharacterName where

    characterName = lens getter setter
      where
         getter e   = metadata e ^. characterName
         setter e x = e { metadata = metadata e &  characterName .~ x }


-- | (✔)
instance HasCharacterSymbolTransitionCostMatrixGenerator (DiscreteDecoration c) (Int -> Int -> Int) where

    characterSymbolTransitionCostMatrixGenerator = lens getter setter
      where
         getter e   = metadata e ^. characterSymbolTransitionCostMatrixGenerator
         setter e f = e { metadata = metadata e &  characterSymbolTransitionCostMatrixGenerator .~ f }


-- | (✔)
instance HasCharacterTransitionCostMatrix (DiscreteDecoration c) (c -> c -> (c, Int)) where

    characterTCM = lens getter setter
      where
         getter e   = metadata e ^. characterTCM
         setter e f = e { metadata = metadata e &  characterTCM .~ f }


-- | (✔)
instance HasCharacterWeight (DiscreteDecoration c) Double where

    characterWeight = lens getter setter
      where
         getter e   = metadata e ^. characterWeight
         setter e x = e { metadata = metadata e &  characterWeight .~ x }


-- | (✔)
instance GeneralCharacterMetadata (DiscreteDecoration c) where


-- | (✔)
instance EncodableStreamElement c => DiscreteCharacterMetadata (DiscreteDecoration c) c where


-- | (✔)
instance EncodableStaticCharacter c => DiscreteCharacterDecoration (DiscreteDecoration c) c where


-- | (✔)
instance EncodableStaticCharacter c => SimpleDiscreteCharacterDecoration (DiscreteDecoration c) c where
    toDiscreteCharacterDecoration name weight alphabet tcm g symbolSet =
        DiscreteDec
        { discreteDecorationCharacter = g symbolSet
        , metadata                    = discreteMetadata name weight alphabet tcm
        }
