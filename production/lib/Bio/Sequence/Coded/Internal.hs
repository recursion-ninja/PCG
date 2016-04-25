-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Sequences.Coded.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Concrete data structures for coded sequences
-----------------------------------------------------------------------------

{-# LANGUAGE TypeSynonymInstances, FlexibleInstances, MultiParamTypeClasses, UndecidableInstances #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Bio.Sequence.Coded.Internal where

import           Prelude        hiding (and, head, or)
import           Bio.Sequence.Coded.Class
import           Bio.Sequence.Character.Coded
import           Bio.Sequence.Packed.Class
import           Bio.Sequence.Parsed
import           Control.Applicative   (liftA2)
import           Control.Monad
import           Data.Bits
import           Data.BitVector hiding (foldr, foldl, join, not)
import           Data.Function.Memoize
import           Data.Maybe
import           Data.Monoid           ((<>))
import           Data.Vector           (fromList, Vector)
import           Test.Tasty.QuickCheck (Arbitrary, arbitrary, listOf, Gen)

-- TODO: Change EncodedSeq/Sequences to EncodedCharacters
        -- Make a missing a null vector
        -- Think about a nonempty type class or a refinement type for this

-- | EncodedSequences is short for a vector of EncodedSeq
type EncodedSequences = Vector EncodedSeq

-- | An EncodedSeq (encoded sequence) is a maybe vector of characters
-- TODO: Can we get rid of this Maybe, and just set to [0]0, instead?
-- TODO: change name to make clear the difference between a CodedSequence and an EncodedSeq
type EncodedSeq = Maybe BitVector

-- | Make EncodedSeq an instance of CodedSequence
instance CodedSequence EncodedSeq where
    charToSeq = Just
    decodeOverAlphabet encoded alphabet = case encoded of 
        Nothing        -> mempty
        (Just allBits) -> decodedSeq
            where 
                alphLen = length alphabet
                decodedSeq = fromList $ foldr (\theseBits acc -> decodeOneChar theseBits alphabet : acc) [] (group alphLen allBits)
    emptySeq = Nothing -- TODO: Should this be Just $ bitVec alphLen 0?
    -- This works over minimal alphabet
    encode inSeq = encodeOverAlphabet inSeq alphabet 
        where
            -- Get the alphabet from the sequence (if for some reason it's not previously defined).
            alphabet = foldr (\ambig acc -> filter (`notElem` acc) ambig <> acc) [] inSeq
    encodeOverAlphabet inSeq alphabet 
        | null inSeq = Nothing
        | otherwise  = Just $ foldr (\x acc -> createSingletonChar alphabet x <> acc ) zeroBits inSeq 
    filterGaps inSeq gap alphabet = 
        case gap of 
          Nothing     -> inSeq
          Just gapVal -> 
            case inSeq of
              Nothing      -> inSeq
              Just bitsVal -> Just . foldr (f gapVal) zeroBits $ group alphLen bitsVal
        where 
            alphLen = length alphabet
            f gapVal x acc = if   x ==. gapVal
                             then x <> acc
                             else acc

    grabSubChar inSeq pos alphLen = extract left right <$> inSeq
        where
            left = ((pos + 1) * alphLen) - 1
            right = pos * alphLen
    isEmpty seqs = case seqs of
        Nothing -> True
        Just x  -> x /= zeroBits -- TODO: Is this right?
    numChars s alphLen = case s of 
        Nothing  -> 0
        Just vec -> width vec `div` alphLen
    

instance Bits EncodedSeq where
    (.&.)           = liftA2 (.&.)
    (.|.)           = liftA2 (.|.)
    xor             = liftA2 xor
    complement      = fmap complement
    shift  bits s   = fmap (`shift`  s) bits
    rotate bits r   = fmap (`rotate` r) bits
    setBit bits s   = fmap (`setBit` s) bits
    bit             = Just . bit
    bitSize         = fromMaybe 0 . (bitSizeMaybe =<<)
    bitSizeMaybe    = (bitSizeMaybe =<<)
    isSigned        = maybe False isSigned
    popCount        = maybe 0 popCount
    testBit bits i  = maybe False (`testBit` i) bits

instance Memoizable BitVector where
    memoize f char = memoize (f . bitVec w) (nat char)
                        where w = width char

instance PackedSequence EncodedSeq where
    packOverAlphabet = undefined

instance CodedChar EncodedSeq where
    gapChar alphLen = Just $ gapChar alphLen

instance CodedChar BitVector where
    gapChar alphLen = setBit (bitVec alphLen (0 :: Int)) 0

instance Arbitrary BitVector where
    arbitrary = fromBits <$> listOf (arbitrary :: Gen Bool)

instance Arbitrary b => Arbitrary (Vector b) where
    arbitrary = fromList <$> listOf arbitrary

-- | Get parsed sequenceS, return encoded sequenceS.
-- Recall that each is Vector of Maybes, to this type is actually
-- Vector Maybe Vector [String] -> Vector Maybe BV.
-- (I only wish I were kidding.)
encodeAll :: ParsedSequences -> EncodedSequences
encodeAll = fmap (\s -> join $ encode <$> s)

-- | Simple functionality to set a single element in a BitVector
-- That element is a singleton character, but may be ambiguous
-- For quickness, hardcoded as BV, so I could use fromBits.
-- If we generalize later, I'll have to update this.
createSingletonChar :: Alphabet -> AmbiguityGroup -> BitVector 
createSingletonChar alphabet inChar = bitRepresentation
    where 
        -- For each (yeah, foreach!) letter in (ordered) alphabet, decide whether it's present in the ambiguity group.
        -- Collect into [Bool].
        bits = fmap (`elem` inChar) alphabet
        bitRepresentation = fromBits bits

-- | Takes a single 
decodeOneChar :: BitVector -> Alphabet -> [String] 
decodeOneChar inBV alphabet = foldr (\(charValExists, char) acc -> if charValExists 
                                                                   then char : acc 
                                                                   else acc
                                              ) [] (zip (toBits inBV) alphabet)

-- | Functionality to unencode many
decodeMany :: EncodedSequences -> Alphabet -> ParsedSequences
decodeMany seqs alph = fmap (Just . flip decodeOverAlphabet alph) seqs