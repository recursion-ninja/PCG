-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Character.Static.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Data structures and instances for coded characters
-- Coded characters are dynamic characters recoded as 
--
-----------------------------------------------------------------------------

-- TODO: Remove all commented-out code.

-- TODO: are all of these necessary?
{-# LANGUAGE GeneralizedNewtypeDeriving, TypeFamilies #-}
-- TODO: fix and remove this ghc option (is it needed for Arbitrary?):
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Bio.Character.Static.Internal
  ( StaticCharacter()
  , StaticCharacterBlock()
  ) where

import           Bio.Character.Static.Class
import           Bio.Character.Stream
import           Bio.Character.Exportable.Class
import           Control.Arrow                       ((***))
import           Data.Alphabet
import           Data.Bifunctor                      (bimap)
import           Data.BitMatrix
import           Data.BitMatrix.Internal(BitMatrix(..))
import           Data.Char                           (toLower)
import           Data.Key
import           Data.Bits
import           Data.BitVector               hiding (foldr, join, not, replicate)
import           Data.Foldable
import qualified Data.List.NonEmpty           as NE
import qualified Data.Map                     as M
import           Data.Monoid                  hiding ((<>))
import           Data.MonoTraversable
import           Data.Semigroup
import           Data.String                         (fromString)
import           Data.Tuple                          (swap)
import           Prelude                      hiding (lookup)
import           Test.Tasty.QuickCheck        hiding ((.&.))
import           Test.QuickCheck.Arbitrary.Instances ()

--import Debug.Trace

-- TODO: Change DynamicChar/Sequences to DynamicCharacters
        -- Make a missing a null vector
        -- Think about a nonempty type class or a refinement type for this

newtype StaticCharacter
      = SC BitVector
      deriving (Bits, Eq, Enum, Num, Ord, Show)


-- | Represents an encoded dynamic character, consisting of one or more static
--   characters. Dynamic characters treat entire static characters as the
--   character states of the dynamic character. The dynamic character relies on
--   the encoding of the individual static characters to defined the encoding of
--   the entire dynamic character.
newtype StaticCharacterBlock
      = SCB BitMatrix
      deriving (Eq, Show)


type instance Element StaticCharacterBlock = StaticCharacter


instance MonoFunctor StaticCharacterBlock where

    omap f = SCB . omap (unwrap . f . SC) . unstream
  

instance Semigroup StaticCharacterBlock where

    (SCB lhs) <> (SCB rhs)
      | m == n    = SCB . expandVector m $ collapseRows lhs `mappend` collapseRows rhs
      | otherwise = error $ unwords ["Attempt to concatentate two StaticCharacterBlock of differing stateCounts:", show m, show n]
      where
        m = numCols lhs
        n = numCols rhs


instance MonoFoldable StaticCharacterBlock where

    -- | Map each element of a monomorphic container to a 'Monoid'
    -- and combine the results.
    {-# INLINE ofoldMap #-}
    ofoldMap f = ofoldMap (f . SC) . unstream

    -- | Right-associative fold of a monomorphic container.
    {-# INLINE ofoldr #-}
    ofoldr f e = ofoldr (f . SC) e . unstream

    -- | Strict left-associative fold of a monomorphic container.
    {-# INLINE ofoldl' #-}
    ofoldl' f e = ofoldl' (\acc x -> f acc (SC x)) e . unstream

    -- | Right-associative fold of a monomorphic container with no base element.
    --
    -- Note: this is a partial function. On an empty 'MonoFoldable', it will
    -- throw an exception.
    --
    -- /See 'Data.MinLen.ofoldr1Ex' from "Data.MinLen" for a total version of this function./
    {-# INLINE ofoldr1Ex #-}
    ofoldr1Ex f = SC . ofoldr1Ex (\x y -> unwrap $ f (SC x) (SC y)) . unstream

    -- | Strict left-associative fold of a monomorphic container with no base
    -- element.
    --
    -- Note: this is a partial function. On an empty 'MonoFoldable', it will
    -- throw an exception.
    --
    -- /See 'Data.MinLen.ofoldl1Ex'' from "Data.MinLen" for a total version of this function./
    {-# INLINE ofoldl1Ex' #-}
    ofoldl1Ex' f = SC . ofoldl1Ex' (\x y -> unwrap $ f (SC x) (SC y)) . unstream

    {-# INLINE onull #-}
    onull = const False

    {-# INLINE olength #-}
    olength = numRows . unstream


-- | Monomorphic containers that can be traversed from left to right.
instance MonoTraversable StaticCharacterBlock where

    -- | Map each element of a monomorphic container to an action,
    -- evaluate these actions from left to right, and
    -- collect the results.
    {-# INLINE otraverse #-}
    otraverse f = fmap SCB . otraverse (fmap unwrap . f . SC) . unstream

    -- | Map each element of a monomorphic container to a monadic action,
    -- evaluate these actions from left to right, and
    -- collect the results.
    {-# INLINE omapM #-}
    omapM = otraverse


instance EncodableStreamElement StaticCharacter where

    decodeElement alphabet character = NE.fromList $ foldMapWithKey f alphabet
      where
        f i symbol
          | character `testBit` i = [symbol]
          | otherwise             = []

    -- Use foldl here to do an implicit reversal of the alphabet!
    -- The head element of the list is the most significant bit when calling fromBits.
    -- We need the first element of the alphabet to correspond to the least significant bit.
    -- Hence foldl, don't try foldMap or toList & fmap without careful thought.
    encodeElement alphabet ambiguity = SC . fromBits $ foldl' (\xs x -> (x `elem` ambiguity) : xs) [] alphabet

    stateCount = width . unwrap


instance EncodableStaticCharacter StaticCharacter



instance EncodableStream StaticCharacterBlock where

    decodeStream alphabet char
      | alphabet /= dnaAlphabet = rawResult 
      | otherwise               = (dnaIUPAC !) <$> rawResult
      where
        rawResult   = NE.fromList . ofoldMap (pure . decodeElement alphabet) . otoList $ char
        dnaAlphabet = fromSymbols $ fromString <$> ["A","C","G","T"]
--        dnaIUPAC :: (IsString a, Ord a) => Map [a] [a]
        dnaIUPAC    = M.fromList . fmap (swap . (NE.fromList . pure . fromChar *** NE.fromList . fmap fromChar)) $ mapping
          where
            fromChar = fromString . pure
            mapping  = gapMap <> noGapMap <> [('-', "-")]
            gapMap   = (toLower *** (<> "-")) <$> noGapMap
            noGapMap =
              [ ('A', "A"   )
              , ('C', "C"   )
              , ('G', "G"   )
              , ('T', "T"   )
              , ('M', "AC"  ) 
              , ('R', "AG"  )
              , ('W', "AT"  )
              , ('S', "CG"  )
              , ('Y', "CT"  )
              , ('K', "GT"  )
              , ('V', "ACG" )
              , ('H', "ACT" )
              , ('D', "AGT" )
              , ('B', "CGT" )
              , ('N', "ACGT")
              ]

    encodeStream alphabet = SCB . fromRows . fmap (unwrap . encodeElement alphabet) . toList

    lookupStream (SCB bm) i
      | 0 <= i && i < numRows bm = Just . SC $ bm `row` i
      | otherwise                = Nothing


instance EncodableStaticCharacterStream StaticCharacterBlock where

    constructStaticStream = SCB . fromRows . fmap unwrap . toList


instance Arbitrary StaticCharacterBlock where
    arbitrary = do 
        symbolCount  <- arbitrary `suchThat` (\x -> 0 < x && x <= 62) :: Gen Int
        characterLen <- arbitrary `suchThat` (> 0) :: Gen Int
        let randVal  =  choose (1, 2 ^ symbolCount - 1) :: Gen Integer
        bitRows      <- vectorOf characterLen randVal
        pure . SCB . fromRows $ bitVec symbolCount <$> bitRows


instance Exportable StaticCharacterBlock where
    toExportable (SCB bm@(BitMatrix _ bv)) =
        ExportableCharacterSequence
        { elementCount = x
        , elementWidth = y
        , bufferChunks = fmap fromIntegral $ ((bv @@) <$> slices) <> tailWord
        }
      where
        x = numRows bm
        y = numCols bm
        totalBits = x * y
        (fullWords, remainingBits) = totalBits `divMod` 64
        slices   = take fullWords $ iterate ((64 +) `bimap` (64 +)) ((63, 0) :: (Int,Int))
        tailWord = if   remainingBits == 0
                   then []
                   else [ bv @@ (totalBits - 1, totalBits - remainingBits) ]
        
    fromExportable = undefined


{-# INLINE unstream #-}
unstream :: StaticCharacterBlock -> BitMatrix
unstream (SCB x) = x


{-# INLINE unwrap #-}
unwrap :: StaticCharacter -> BitVector
unwrap (SC x) = x
