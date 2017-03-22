-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Character.Encodable.Continuous.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts, FlexibleInstances, MultiParamTypeClasses, TypeFamilies #-}

module Bio.Character.Encodable.Continuous.Internal where


import Bio.Character.Encodable.Internal
import Data.ExtendedReal
import Data.Range


newtype ContinuousChar = CC (ExtendedReal, ExtendedReal)
  deriving (Eq)


-- | (✔)
instance Show ContinuousChar where

    show (CC (lower, upper))
      | lower == upper = show lower
      | otherwise      = renderRange lower upper
      where
        renderRange x y = mconcat [ "[", show x, ", ", show y, "]" ]


-- | (✔)
instance PossiblyMissingCharacter ContinuousChar where

    {-# INLINE toMissing #-}
    toMissing = const . CC $ (minBound, maxBound)

    {-# INLINE isMissing #-}
    isMissing (CC (x,y)) = x == minBound && y == maxBound
    isMissing _          = False 


-- -- | (✔)
-- instance PossiblyMissingCharacter ContinuousChar where

--     {-# INLINE toMissing #-}
--     toMissing = const $ CC Nothing

--     {-# INLINE isMissing #-}
--     isMissing (CC Nothing) = True
--     isMissing _            = False


{-
-- | (✔)
instance ContinuousCharacter ContinuousChar where

    toContinuousCharacter = CC . fmap (fromRational . toRational)
-}


type instance Bound ContinuousChar = ExtendedReal


instance Ranged ContinuousChar where

    toRange (CC interval) = fromTuple interval

    fromRange interval = CC (lowerBound interval, upperBound interval)

    zeroRange _ = fromTuple (0,0)

