{-# LANGUAGE FlexibleInstances #-}

module Bio.Character.Dynamic.Coded.Test
  ( testSuite
  ) where

import Bio.Character.Dynamic.Coded
import Bio.Character.Parsed
import Data.Alphabet
import Data.Bits
import Data.BitVector (BitVector, bitVec, toBits, width)
import Data.Foldable
import Data.Key       ((!))
import qualified Data.Set as Set (fromList,intersection,union)
import Data.Monoid    ((<>))
import Data.Vector    (Vector, fromList)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck hiding ((.&.))

import Debug.Trace

testSuite :: TestTree
testSuite = testGroup "Custom Bits instances"
        [ testVectorBits
        , testCodedSequenceInstance
        --, overEmpties
        , testEncodableStaticCharacterInstanceBitVector
        , testEncodableDynamicCharacterInstanceDynamicChar
        ]

testVectorBits :: TestTree
testVectorBits = testGroup "Properties of instance Bits b => Bits (Vector b)"
        [ testZeroBitProperties         zeroBitsDynamic "dynamic"
        , testBitConstructionProperties zeroBitsDynamic "dynamic"
        ]
    where
        zeroBitsDynamic = zeroBits :: DynamicChar

testZeroBitProperties :: Bits b => b -> String -> TestTree
testZeroBitProperties z label = testGroup ("zeroBit properties (" <> label <> ")")
        [ zeroBitsID
        , setBitBitEquivalency
        , zeroBitIsAllZeroes
        , popCountZeroBitIs0
        ]
    where
        zeroBitsID :: TestTree
        zeroBitsID = testProperty "clearBit zeroBits n == zeroBits" f
            where
                f :: NonNegative Int -> Bool
                f n = let i = getNonNegative n
                      in  clearBit z i == z
        setBitBitEquivalency :: TestTree
        setBitBitEquivalency = testProperty "setBit zeroBits n == bit n" f
            where
                f :: NonNegative Int -> Bool
                f n = let i = getNonNegative n
                      in  setBit z i == bit i

        zeroBitIsAllZeroes :: TestTree
        zeroBitIsAllZeroes = testProperty "testBit zeroBits n == False" f
            where
                f :: NonNegative Int -> Bool
                f n = let i = getNonNegative n
                      in  not $ testBit z i

        popCountZeroBitIs0 :: TestTree
        popCountZeroBitIs0 = testCase "popCount zeroBits == 0" . assert $ popCount z == 0

testBitConstructionProperties :: Bits b => b -> String -> TestTree
testBitConstructionProperties z label = testGroup ("Bit toggling properties (" <> label <> ")")
        [ setBitTestBit
        , bitClearBit
        ]
    where
        setBitTestBit :: TestTree
        setBitTestBit = testProperty "testBit (setBit zeroBits i) i == True" f
            where
                f :: NonNegative Int -> Bool
                f n = let i = getNonNegative n
                      in  testBit (setBit z i) i
        bitClearBit :: TestTree
        bitClearBit = testProperty "clearBit (bit i) i == zeroBits" f
            where
                f :: NonNegative Int -> Bool
                f n = let i = getNonNegative n
                      in  clearBit (bit i) i == z

testCodedSequenceInstance :: TestTree
testCodedSequenceInstance = testGroup "Properties of instance CodedSequence EncodedSeq"
        [ --decodeOverAlphabet
        encodeOverAlphabetTest
        --, filterGaps
        --, grabSubChar
        --, isEmpty
        --, numChars
        ]

encodeOverAlphabetTest :: TestTree
encodeOverAlphabetTest = testGroup "encodeOverAlphabet"
    [ testAlphabetLen
    --, testValue
    ]
    where
        testAlphabetLen = testProperty "Make sure alphabet length of encoded dynamic char == len(alphabet)." f
            where
                f :: (ParsedChar', Alphabet) -> Bool
                f (inChar, alph) = getAlphLen (encodeOverAlphabet alph (getParsedChar inChar) :: DynamicChar) == length alph
        {-testValue = testProperty "Make sure encoded value matches position in alphabet." f
            where
                -- for each ambiguity group in inChar, map over the alphabet determining whether each alphabet state exists in the ambiguity group
                f :: (ParsedChar', Alphabet) -> Bool
                f (inChar, alph) = toBits controlChar == (fmap (\c -> elem c alph) $ toList charToTest)
                    where 
                        charToTest  = getParsedChar inChar
                        controlChar = (encodeOverAlphabet alph charToTest :: DynamicChar)-}
{-
overEmpties :: TestTree
overEmpties = testGroup "Verify function over empty structures" [filt]
    where
        filt = testCase "FilterGaps works over empty" ((filterGaps emptyChar) @?= emptyChar)
-}
type DynamicChar' = Vector

type ParsedChar' = Vector (NonEmptyList (NonEmptyList Char))

getParsedChar :: ParsedChar' -> ParsedChar
getParsedChar = fmap (fmap getNonEmpty . getNonEmpty)

--decodeOverAlphabetTest :: TestTree
--decodeOverAlphabetTest = testProperty "decodeOverAlphabet" f
--    where
--        f :: CodedSequence s -> Alphabet -> ParsedChar
--        f inChar alph =

instance Arbitrary (ParsedChar', Alphabet) where
    arbitrary = do
        alphabet <- (fmap (:[]) . getNonEmpty) <$> (arbitrary :: (Gen (NonEmptyList Char)))
        vector   <- fmap (fmap (NonEmpty . (:[]) . NonEmpty) . fromList) . listOf1 $ elements alphabet
        pure (vector, fromList alphabet)


{- LAWS:
 - decodeChar alphabet . encodeChar alphabet . toList == id
 - encodeChar alphabet [alphabet !! i] == bit i
 - encodeChar alphabet alphabet == complement zeroBits
 - decodeChar alphabet (encodeChar alphabet xs .|. encodeChar alphabet ys) == toList alphabet `Data.List.intersect` (toList xs `Data.List.union` toList ys)
 - decodeChar alphabet (encodeChar alphabet xs .&. encodeChar alphabet ys) == toList alphabet `Data.List.intersect` (toList xs `Data.List.intersect` toList ys)
 -}
testEncodableStaticCharacterInstanceBitVector :: TestTree
testEncodableStaticCharacterInstanceBitVector = testGroup "BitVector instance of EncodableDynamicCharacter" [testLaws]
  where
    encodeChar' :: Foldable t => Alphabet' String -> t String -> BitVector
    encodeChar' = encodeChar
    testLaws = testGroup "EncodableDynamicChar Laws"
             [ encodeDecodeIdentity
             , singleBitConstruction
             , totalBitConstruction
             , logicalOrIsomorphismWithSetUnion
             , logicalAndIsomorphismWithSetIntersection
             ]
      where
        encodeDecodeIdentity = testProperty "Set.fromList . decodeChar alphabet . encodeChar alphabet . Set.fromList . toList == Set.fromList . toList" f
          where
            f :: (Alphabet' String, [String]) -> Bool
            f (alphabet, ambiguityGroup) = lhs ambiguityGroup == rhs ambiguityGroup
              where
                lhs = Set.fromList . decodeChar alphabet . encodeChar' alphabet . Set.fromList . toList
                rhs = Set.fromList . toList
        singleBitConstruction = testProperty "encodeChar alphabet [alphabet ! i] == bit i" f
          where
            f :: Alphabet' String -> NonNegative Int -> Bool
            f alphabet (NonNegative n) = encodeChar' alphabet [alphabet ! i] == bit i
              where
                i = n `mod` length alphabet
        totalBitConstruction = testProperty "encodeChar alphabet alphabet == complement (bit (length alphabet - 1) `clearBit` (bit (length alphabet - 1))" f
          where
            f :: Alphabet' String -> Bool
            f alphabet = encodeChar' alphabet alphabet == e
              where
                e = complement $ bit i `clearBit` i
                i = length alphabet - 1
        logicalOrIsomorphismWithSetUnion = testProperty "Set.fromList (decodeChar alphabet (encodeChar alphabet xs .|. encodeChar alphabet ys)) == Set.fromList (toList alphabet) `Set.intersect` (toList xs `Set.union` toList ys)" f
          where
            f :: (Alphabet' String, [String], [String]) -> Bool
            f (alphabet, xs, ys) = lhs == rhs
              where
                lhs = Set.fromList $ decodeChar alphabet (encodeChar' alphabet sxs .|. encodeChar' alphabet sys)
                rhs = sxs `Set.union` sys
                sxs = Set.fromList xs
                sys = Set.fromList ys
        logicalAndIsomorphismWithSetIntersection = testProperty "Set.fromList (decodeChar alphabet (encodeChar alphabet xs .&. encodeChar alphabet ys)) == Set.fromList (toList alphabet) `Set.intersect` (toList xs `Set.intersection` toList ys)" f
          where
            f :: (Alphabet' String, [String], [String]) -> Bool
            f (alphabet, xs, ys) = lhs == rhs
              where
                lhs = Set.fromList $ decodeChar alphabet (encodeChar' alphabet sxs .&. encodeChar' alphabet sys)
                rhs = sxs `Set.intersection` sys
                sxs = Set.fromList xs
                sys = Set.fromList ys

{- LAWS:
 - decodeMany alphabet . encodeMany alphabet == fmap toList . toList
 - TODO: Add more laws here
 -}
testEncodableDynamicCharacterInstanceDynamicChar :: TestTree
testEncodableDynamicCharacterInstanceDynamicChar = testGroup "BitVector instance of EncodableDynamicCharacter" [testLaws]
  where
    testLaws = testGroup "EncodableDynamicChar Laws"
             [ encodeDecodeIdentity
--             , singleBitConstruction
--             , totalBitConstruction
--             , logicalOrIsomorphismWithSetUnion
--             , logicalAndIsomorphismWithSetIntersection
             ]
      where
        encodeDecodeIdentity = testProperty "decodeDynamic alphabet . encodeDynamic alphabet == fmap toList . toList" f
          where
            f :: (Alphabet' String, [[String]]) -> Bool
            f (alphabet, dynamicChar) = lhs dynamicChar == rhs dynamicChar
              where
                enc :: (Foldable t) => t (t String) -> DynamicChar
                enc = encodeDynamic alphabet
                lhs = fmap Set.fromList . decodeDynamic alphabet . enc
                rhs = fmap Set.fromList . toList




instance Arbitrary (Alphabet' String, [String]) where
  arbitrary = do
    (alphabet,[x]) <- alphabetAndAmbiguityGroups 1
    pure (alphabet, x)

instance Arbitrary (Alphabet' String, [String], [String]) where
  arbitrary = do
    (alphabet,[x,y]) <- alphabetAndAmbiguityGroups 2
    pure (alphabet, x, y)

instance Arbitrary (Alphabet' String, [[String]]) where
  arbitrary = do
    alphabet    <- arbitrary :: Gen (Alphabet' String)
    let ambiguityGroup = listOf . elements $ toList alphabet
    dynamicChar <- listOf1 ambiguityGroup
    pure (alphabet, dynamicChar)

--instance Arbitrary (Alphabet' String) where
--  arbitrary = constructAlphabet . getNonEmpty <$> (arbitrary :: Gen (NonEmptyList String))

alphabetAndAmbiguityGroups :: Int -> Gen (Alphabet' String, [[String]])
alphabetAndAmbiguityGroups n = do
   alphabet        <- arbitrary :: Gen (Alphabet' String)
   let ambiguityGroup = listOf . elements $ toList alphabet -- list can be empty, can have duplicates!
   ambiguityGroups <- vectorOf n ambiguityGroup
   pure (constructAlphabet alphabet, ambiguityGroups)
                                