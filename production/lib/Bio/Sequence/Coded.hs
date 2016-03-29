-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Sequences.Coded
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Data structures and instances for coded sequences
--
-----------------------------------------------------------------------------


{-# LANGUAGE TypeSynonymInstances, FlexibleInstances, MultiParamTypeClasses, UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Bio.Sequence.Coded (CodedSequence(..), EncodedSeq, EncodedSequences, CodedChar(..), encodeAll, unencodeMany) where

import           Prelude hiding (map, zipWith, null, head)
import           Bio.Sequence.Coded.Class
import           Bio.Sequence.Character.Coded
import           Bio.Sequence.Packed.Class
import           Bio.Sequence.Parsed
import           Control.Applicative  (liftA2, liftA)
import           Control.Monad
import           Data.Bits
import           Data.BitVector (BitVector, size, )
import           Data.List (elemIndex)
import           Data.Maybe
import           Data.Vector    (map, zipWith, empty, Vector, head, (!), singleton)
import qualified Data.Vector as V (filter)

import GHC.Stack
import Data.Foldable
-- import Debug.Trace

-- TODO: Change EncodedSeq/Sequences to EncodedCharacters
        -- Make a missing a null vector
        -- Think about a nonempty type class or a refinement type for this

-- | EncodedSequences is short for a vector of EncodedSeq
type EncodedSequences = Vector EncodedSeq

-- | An EncodedSeq (encoded sequence) is a maybe vector of characters
type EncodedSeq = Maybe BitVector

-- | Make a coded sequence and coded character instances of bits
instance Bits b => CodedSequence EncodedSeq where
    numChars s = case s of 
        Nothing -> 0
        Just vec -> width vec
    charToSeq = Just . singleton
    grabSubChar s pos = liftA (! pos) s
    emptySeq = Nothing
    isEmpty = isNothing
    filterSeq s condition = liftA (V.filter condition) s
    -- This works over minimal alphabet
    encode strSeq = 
        let 
            alphabet = foldr (\ambig acc -> filter (not . flip elem acc) ambig ++ acc) [] strSeq
            coded = map (foldr (\c acc -> setElemAt c acc alphabet) zeroBits) strSeq
            final = if null coded then Nothing else Just coded
        in final

    encodeOverAlphabet strSeq inAlphabet = 
        let
            alphabet = inAlphabet
            coded = map (foldr (\c acc -> setElemAt c acc alphabet) zeroBits) strSeq
            final = if null coded then Nothing else Just coded
        in {- trace ("encoded strSeq " ++ show strSeq) -} final

----  = 
--    let
--        alphWidth = length alphabet
--        bitWidth = bitSizeMaybe gapChar
--        coded = map (\ambig -> foldr (\c acc -> setElemAt c acc alphabet) zeroBits ambig) strSeq
--        regroup = case bitWidth of
--                    Nothing -> ifoldr (\i val acc -> shift val (i * alphWidth) + acc) zeroBits coded
--                    Just width -> let grouped = foldr (\i acc -> (slice i alphWidth coded) ++ acc) mempty [alphWidth, 2 * alphWidth..width - alphWidth]
--                                  in P.map (\g -> ifoldr (\i val acc -> shift val (i * alphWidth) + acc)) grouped
--    in undefined

-- | Sequence to map encoding over ParsedSequences
encodeAll :: Bits b => ParsedSequences -> EncodedSequences b
encodeAll = fmap (\s -> join $ encode <$> s)

instance Bits b => PackedSequence (EncodedSeq b) b where
    packOverAlphabet = undefined

setElemAt :: (Bits b) => String -> b -> [String] -> b
setElemAt char orig alphabet
    | char == "-" = setBit orig 0
    | otherwise = case elemIndex char alphabet of
                        Nothing -> orig
                        Just pos -> setBit orig (pos + 1)    

-- | Added functionality for unencoded
unencodeOverAlphabet :: EncodedSeq BitVector -> Alphabet -> ParsedSeq 
unencodeOverAlphabet encoded alph = 
    let 
        alphLen = length alph
        oneBit inBit = foldr (\i acc -> if testBit inBit i then alph !! (i `mod` alphLen) : acc else acc) mempty [0..size inBit]
        allBits = fmap oneBit <$> encoded
    in fromMaybe mempty allBits

-- | Functionality to unencode many
unencodeMany :: EncodedSequences BitVector -> Alphabet -> ParsedSequences
unencodeMany seqs alph = fmap (Just . flip unencodeOverAlphabet alph) seqs

instance Bits b => CodedChar b where
    gapChar = setBit zeroBits 0

-- | To make this work, the underlying types are also an instance of bits because a Vector of bits is and a Maybe bits is
instance Bits b => Bits (Vector b) where
    (.&.) bit1 bit2     
        | length bit1 /= length bit2 = errorWithStackTrace $ "Attempt to take and of bits of different length " ++ show (length bit1) ++ " and " ++ show (length bit2)
        | otherwise = zipWith (.&.) bit1 bit2
    (.|.) bit1 bit2 
        | length bit1 /= length bit2 = error "Attempt to take or of bits of different length"
        | otherwise = zipWith (.|.) bit1 bit2
    xor bit1 bit2 = (.&.) ((.|.) bit1 bit2) (complement ((.&.) bit1 bit2))
    complement    = map complement
    shift  bits s = (`shift`  s) <$> bits
    rotate bits r = (`rotate` r) <$> bits
    setBit _    _ = empty -- these methods are not meaningful so they just wipe it
    bit    pos    = pure $ bit pos
    bitSize       = foldl' (\a b -> fromMaybe 0 (bitSizeMaybe b) + a) 0
    bitSizeMaybe  = foldlM (\a b -> (a+) <$> bitSizeMaybe b) 0 
    isSigned _    = False
    popCount      = foldr (\b acc -> acc + popCount b) 0
    testBit bits index
        | null bits = False
        | otherwise =
          case bitSizeMaybe $ head bits of
            Nothing      -> False
            Just numBits -> let (myBit, myPos) = index `divMod` numBits
                            in testBit (bits ! myBit) myPos
     -- zeroBits = clearBit (bit 0) 0
     --          = (bit 0) .&. complement (bit 0)
     --          = (bit 0) .&. (bit 0)
     --          = empty .&. empty 
     --          = empty

instance Bits b => Bits (Maybe b) where
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
    testBit  bits i = maybe False (`testBit` i) bits
