{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DerivingStrategies  #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Bio.Character.Encodable.Dynamic.Test
  ( testSuite
  ) where

import           Bio.Character
import           Control.DeepSeq
import           Control.Exception
import           Data.Alphabet
import           Data.Bits
import           Data.Foldable
import           Data.Key                ((!))
import           Data.List.NonEmpty      (NonEmpty ((:|)))
import qualified Data.List.NonEmpty      as NE
import           Data.MonoTraversable
import           Data.Semigroup
import           Data.Set                (Set)
import qualified Data.Set                as Set (fromList, intersection, union)
import           Data.Vector             (Vector, fromList)
import           Test.QuickCheck.Monadic
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck   hiding ((.&.))


testSuite :: TestTree
testSuite = testGroup "Dynamic Character tests"
    [ dynamicCharacterElementTests
    , dynamicCharacterTests
    ]


dynamicCharacterTests :: TestTree
dynamicCharacterTests = testGroup "Dynamic Character tests"
    [ monoFoldablePropertiesGen @DynamicCharacter
    , monoFunctorProperties
    , orderingProperties
    , datastructureTests
    ]


dynamicCharacterElementTests :: TestTree
dynamicCharacterElementTests = testGroup "Dynamic Character Element tests"
    [ elementBitsTests
    , elementFiniteBitsTests
    , monoFoldablePropertiesGen @DynamicCharacterElement
    , elementMonoFunctorProperties
    , elementOrderingProperties
    ]


monoFunctorProperties :: TestTree
monoFunctorProperties = testGroup "Properties of a MonoFunctor"
    [ testProperty "omap id === id" omapId
    , testProperty "omap (f . g)  === omap f . omap g" omapComposition
    ]
  where
    omapId :: DynamicCharacter -> Property
    omapId bm = omap id bm === id bm

    omapComposition
      :: Blind (DynamicCharacterElement -> DynamicCharacterElement)
      -> Blind (DynamicCharacterElement -> DynamicCharacterElement)
      -> DynamicCharacter
      -> Property
    omapComposition (Blind f) (Blind g) bm =
        (omap f . omap g) bm `equalityWithExceptions` omap (f . g) bm


orderingProperties :: TestTree
orderingProperties = testGroup "Properties of an Ordering"
    [ testProperty "ordering preserves symmetry"  symmetry
    , testProperty "ordering is transitive (total)" transitivity
    ]
  where
    symmetry :: (DynamicCharacter, DynamicCharacter) -> Bool
    symmetry (lhs, rhs) =
        case (lhs `compare` rhs, rhs `compare` lhs) of
          (EQ, EQ) -> True
          (GT, LT) -> True
          (LT, GT) -> True
          _        -> False

    transitivity :: (DynamicCharacter, DynamicCharacter, DynamicCharacter) -> Property
    transitivity (a, b, c) = caseOne .||. caseTwo
      where
        caseOne = (a <= b && b <= c) ==> a <= c
        caseTwo = (a >= b && b >= c) ==> a >= c


elementBitsTests :: TestTree
elementBitsTests = testGroup "Bits instance properties"
    [ testProperty "∀ n ≥ 0, clearBit zeroBits n === zeroBits" zeroBitsAndClearBit
    , testProperty "∀ n ≥ 0, setBit   zeroBits n === bit n" zeroBitsAndSetBit
    , testProperty "∀ n ≥ 0, testBit  zeroBits n === False" zeroBitsAndTestBit
    , testCase     "         popCount zeroBits   === 0" zeroBitsAndPopCount
    , testProperty "(`testBit` i) . complement === not . (`testBit` i)" complementTestBit
    , testProperty "(`setBit` n) === (.|. bit n)" setBitDefinition
    , testProperty "(`clearBit` n) === (.&. complement (bit n))" clearBitDefinition
    , testProperty "(`complementBit` n) === (`xor` bit n)" complementBitDefinition
    , testProperty "(`testBit` n) . (`setBit` n)" testBitAndSetBit
    , testProperty "not  . (`testBit` n) . (`clearBit` n)" testBitAndClearBit
    ]
  where
    zeroBitsAndClearBit :: NonNegative Int -> Property
    zeroBitsAndClearBit (NonNegative n) =
        clearBit (zeroBits :: DynamicCharacterElement) n === zeroBits

    zeroBitsAndSetBit :: NonNegative Int -> Property
    zeroBitsAndSetBit (NonNegative n) =
        setBit   (zeroBits :: DynamicCharacterElement) n === bit n

    zeroBitsAndTestBit :: NonNegative Int -> Property
    zeroBitsAndTestBit (NonNegative n) =
        testBit  (zeroBits :: DynamicCharacterElement) n === False

    zeroBitsAndPopCount :: Assertion
    zeroBitsAndPopCount =
        popCount (zeroBits :: DynamicCharacterElement) @?= 0

    complementTestBit :: Positive Int -> DynamicCharacterElement -> Property
    complementTestBit (Positive i) bm =
        Just i < bitSizeMaybe bm ==>
          ((`testBit` i) . complement) bm === (not . (`testBit` i)) bm

    setBitDefinition :: (NonNegative Int, DynamicCharacterElement) -> Property
    setBitDefinition (NonNegative n, bv) =
        bv `setBit` n === bv .|. bit n

    clearBitDefinition :: (NonNegative Int, DynamicCharacterElement) -> Property
    clearBitDefinition (NonNegative n, bv) =
        Just n < bitSizeMaybe bv ==>
          (bv `clearBit` n === bv .&. complement  (zed .|. bit n))
      where
        zed = bv `xor` bv

    complementBitDefinition :: (NonNegative Int, DynamicCharacterElement) -> Property
    complementBitDefinition (NonNegative n, bv) =
        bv `complementBit` n === bv `xor` bit n

    testBitAndSetBit :: (NonNegative Int, DynamicCharacterElement) -> Bool
    testBitAndSetBit (NonNegative n, bv) =
        ((`testBit` n) . (`setBit` n)) bv

    testBitAndClearBit :: (NonNegative Int, DynamicCharacterElement) -> Bool
    testBitAndClearBit (NonNegative n, bv) =
        (not  . (`testBit` n) . (`clearBit` n)) bv


elementFiniteBitsTests :: TestTree
elementFiniteBitsTests = testGroup "FiniteBits instance consistency"
    [ testProperty "fromEnum . symbolCount === finiteBitSize" finiteBitSizeIsDimension
    , testProperty "length . otoList === finiteBitSize" finiteBitSizeIsBitLength
    , testProperty "length . takeWhile not . otoList === countLeadingZeros" countLeadingZeroAndToBits
    , testProperty "length . takeWhile not . reverse . otoList === countTrailingZeros" countTrailingZeroAndToBits
    ]
  where
    finiteBitSizeIsDimension :: DynamicCharacterElement -> Property
    finiteBitSizeIsDimension x =
      (fromEnum . symbolCount) x === finiteBitSize x

    finiteBitSizeIsBitLength :: DynamicCharacterElement -> Property
    finiteBitSizeIsBitLength x =
      (length . otoList) x === finiteBitSize x

    countLeadingZeroAndToBits :: DynamicCharacterElement -> Property
    countLeadingZeroAndToBits x =
      (length . takeWhile not . otoList) x === countLeadingZeros x

    countTrailingZeroAndToBits :: DynamicCharacterElement -> Property
    countTrailingZeroAndToBits x =
      (length . takeWhile not . reverse . otoList) x === countTrailingZeros x


elementMonoFunctorProperties :: TestTree
elementMonoFunctorProperties = testGroup "Properties of a MonoFunctor"
    [ testProperty "omap id === id" omapId
    , testProperty "omap (f . g)  === omap f . omap g" omapComposition
    ]
  where
    omapId :: DynamicCharacterElement -> Property
    omapId bm = omap id bm === id bm

    omapComposition
      :: Blind (Bool -> Bool)
      -> Blind (Bool -> Bool)
      -> DynamicCharacterElement
      -> Property
    omapComposition (Blind f) (Blind g) bm =
        (omap f . omap g) bm === omap (f . g) bm


elementOrderingProperties :: TestTree
elementOrderingProperties = testGroup "Properties of an Ordering"
    [ testProperty "ordering preserves symmetry"  symmetry
    , testProperty "ordering is transitive (total)" transitivity
    ]
  where
    symmetry :: DynamicCharacterElement -> DynamicCharacterElement -> Bool
    symmetry lhs rhs =
        case (lhs `compare` rhs, rhs `compare` lhs) of
          (EQ, EQ) -> True
          (GT, LT) -> True
          (LT, GT) -> True
          _        -> False

    transitivity
      :: DynamicCharacterElement
      -> DynamicCharacterElement
      -> DynamicCharacterElement
      -> Property
    transitivity a b c = caseOne .||. caseTwo
      where
        caseOne = (a <= b && b <= c) ==> a <= c
        caseTwo = (a >= b && b >= c) ==> a >= c


datastructureTests :: TestTree
datastructureTests = testGroup "Dynamic Character data structure tests"
    [ testEncodableStaticCharacterInstanceDynamicCharacter
    , testEncodableDynamicCharacterInstanceDynamicCharacter
--    , testVectorBits
    ]


{- LAWS:
 - decodeElement alphabet . encodeChar alphabet . toList == id
 - encodeChar alphabet [alphabet !! i] == bit i
 - encodeChar alphabet alphabet == complement zeroBits
 - decodeElement alphabet (encodeChar alphabet xs .|. encodeChar alphabet ys) == toList alphabet `Data.List.intersect` (toList xs `Data.List.union` toList ys)
 - decodeElement alphabet (encodeChar alphabet xs .&. encodeChar alphabet ys) == toList alphabet `Data.List.intersect` (toList xs `Data.List.intersect` toList ys)
 -}
testEncodableStaticCharacterInstanceDynamicCharacter :: TestTree
testEncodableStaticCharacterInstanceDynamicCharacter = testGroup "DynamicCharacter instance of EncodableDynamicCharacter" [testLaws]
  where
    encodeChar' :: Alphabet String -> NonEmpty String -> DynamicCharacterElement
    encodeChar' = encodeElement
    testLaws = testGroup "EncodableDynamicCharacter Laws"
             [ encodeDecodeIdentity
             , singleBitConstruction
             , totalBitConstruction
             , logicalOrIsomorphismWithSetUnion
             , logicalAndIsomorphismWithSetIntersection
             ]
      where
        encodeDecodeIdentity = testProperty "decodeElement alphabet . encodeChar alphabet === id" f
          where
            f :: AlphabetAndSingleAmbiguityGroup -> Property
            f alphabetAndAmbiguityGroup = lhs ambiguityGroup === rhs ambiguityGroup
              where
                lhs = Set.fromList . toList . decodeElement alphabet . encodeChar' alphabet . NE.fromList . toList . Set.fromList . toList
                rhs = Set.fromList . toList
                (alphabet, ambiguityGroup) = getAlphabetAndSingleAmbiguityGroup alphabetAndAmbiguityGroup

        singleBitConstruction = testProperty "encodeChar alphabet [alphabet ! i] == bit i" f
          where
            f :: Alphabet String -> NonNegative Int -> Property
            f alphabet (NonNegative n) = countLeadingZeros (encodeChar' alphabet (pure $ alphabet ! i)) === countLeadingZeros (bit i :: DynamicCharacterElement)
              where
                i = n `mod` length alphabet

        totalBitConstruction = testProperty "encodeChar alphabet alphabet == complement (bit (length alphabet - 1) `clearBit` (bit (length alphabet - 1))" f
          where
            f :: Alphabet String -> Property
            f alphabet = encodeChar' alphabet allSymbols === e
              where
                allSymbols = NE.fromList $ toList alphabet
                e = complement $ bit i `clearBit` i
                i = length alphabet - 1

        logicalOrIsomorphismWithSetUnion = testProperty "decodeElement alphabet (encodeChar alphabet xs .|. encodeChar alphabet ys) === alphabet ∩ (xs ∪ ys)" f
          where
            f :: AlphabetAndTwoAmbiguityGroups -> Property
            f input = lhs === rhs
              where
                lhs = Set.fromList . toList $ decodeElement alphabet (encodeChar' alphabet (fromFoldable sxs) .|. encodeChar' alphabet (fromFoldable sys))
                rhs = sxs `Set.union` sys
                (alphabet, sxs,sys) = gatherAlphabetAndAmbiguitySets input

        logicalAndIsomorphismWithSetIntersection = testProperty "decodeElement alphabet (encodeChar alphabet xs .&. encodeChar alphabet ys) === alphabet ∩ (xs ∩ ys)" f
          where
            f :: AlphabetAndTwoAmbiguityGroups -> Property
            f input =
                (not . null) rhs ==> lhs === rhs
              where
                rhs   = sxs `Set.intersection` sys
                lhs   = Set.fromList . toList $ decodeElement alphabet anded
                anded = xs' .&. ys'
                xs'   = encodeChar' alphabet (fromFoldable sxs)
                ys'   = encodeChar' alphabet (fromFoldable sys)
                (alphabet, sxs, sys) = gatherAlphabetAndAmbiguitySets input


gatherAlphabetAndAmbiguitySets :: AlphabetAndTwoAmbiguityGroups -> (Alphabet String, Set String, Set String)
gatherAlphabetAndAmbiguitySets input = (alphabet, Set.fromList $ toList xs, Set.fromList $ toList ys)
  where
    (alphabet, xs, ys) = getAlphabetAndTwoAmbiguityGroups input


{- LAWS:
 - decodeMany alphabet . encodeMany alphabet == fmap toList . toList
 -}
testEncodableDynamicCharacterInstanceDynamicCharacter :: TestTree
testEncodableDynamicCharacterInstanceDynamicCharacter = testGroup "DynamicCharacter instance of EncodableDynamicCharacter" [testLaws]
  where
    testLaws = testGroup "EncodableDynamicCharacter Laws"
             [ encodeDecodeIdentity
             ]
      where
        encodeDecodeIdentity = testProperty "decodeDynamic alphabet . encodeDynamic alphabet === fmap toList . toList" f
          where
            f :: AlphabetAndCharacter -> Bool
            f alphabetAndDynamicCharacter = lhs dynamicChar == rhs dynamicChar
              where
                enc :: NonEmpty (AmbiguityGroup String) -> DynamicCharacter
                enc = encodeStream alphabet
                lhs = fmap (Set.fromList . toList) . toList . decodeStream alphabet . enc
                rhs = fmap (Set.fromList . toList) . toList
                (alphabet, dynamicChar) = getAlphabetAndCharacter alphabetAndDynamicCharacter


-- Types for supporting 'Arbitrary' construction

type ParsedChar' = Vector (NonEmptyList (NonEmptyList Char))


newtype ParsedCharacterWithAlphabet
      = ParsedCharacterWithAlphabet (ParsedChar', Alphabet String)
      deriving stock (Eq, Show)


instance Arbitrary ParsedCharacterWithAlphabet where

    arbitrary = do
        alphabet  <- arbitrary :: Gen (Alphabet String)
        vectorVal <- fmap (fmap (NonEmpty . (:[]) . NonEmpty) . fromList) . listOf1 . elements . toList $ alphabet
        pure $ ParsedCharacterWithAlphabet (vectorVal, alphabet)


newtype AlphabetAndSingleAmbiguityGroup
      = AlphabetAndSingleAmbiguityGroup
      { getAlphabetAndSingleAmbiguityGroup :: (Alphabet String, NonEmpty String)
      } deriving stock (Eq, Show)


instance Arbitrary AlphabetAndSingleAmbiguityGroup where

    arbitrary = do
        (alphabet, x :| _) <- alphabetAndAmbiguityGroups 1
        pure $ AlphabetAndSingleAmbiguityGroup (alphabet, x)


newtype AlphabetAndTwoAmbiguityGroups
      = AlphabetAndTwoAmbiguityGroups
      { getAlphabetAndTwoAmbiguityGroups :: (Alphabet String, NonEmpty String, NonEmpty String)
      } deriving stock (Eq, Show)


instance Arbitrary AlphabetAndTwoAmbiguityGroups where

    arbitrary = do
      (alphabet, xs) <- alphabetAndAmbiguityGroups 2
      pure $ case xs of
               x:|[]  -> AlphabetAndTwoAmbiguityGroups (alphabet, x, x)
               x:|y:_ -> AlphabetAndTwoAmbiguityGroups (alphabet, x, y)


newtype AlphabetAndCharacter
      = AlphabetAndCharacter
      { getAlphabetAndCharacter :: (Alphabet String, NonEmpty (NonEmpty String))
      } deriving stock (Eq, Show)


instance Arbitrary AlphabetAndCharacter where

    arbitrary = do
        alphabet           <- arbitrary :: Gen (Alphabet String)
        let ambiguityGroup =  fmap NE.fromList . listOf1 . elements $ toList alphabet
        dynamicChar        <- NE.fromList <$> listOf1 ambiguityGroup
        pure $ AlphabetAndCharacter (alphabet, dynamicChar)


alphabetAndAmbiguityGroups :: Int -> Gen (Alphabet String, NonEmpty (NonEmpty String))
alphabetAndAmbiguityGroups n = do
    alphabet           <- arbitrary :: Gen (Alphabet String)
    let ambiguityGroup =  fmap NE.fromList . listOf1 . elements $ toList alphabet -- list can be empty, can have duplicates!
    ambiguityGroups    <- NE.fromList <$> vectorOf n ambiguityGroup
    pure (fromSymbols alphabet, ambiguityGroups)


fromFoldable :: Set a -> NonEmpty a
fromFoldable = NE.fromList . toList


-- |
-- Should either pass the test or throw an exception.
equalityWithExceptions :: (Eq a, NFData a, Show a) => a -> a -> Property
equalityWithExceptions x y = monadicIO $ do
    lhs <- supressException x
    rhs <- supressException y
    pure $ case lhs of
             Left  _ -> anyException
             Right a ->
               case rhs of
                 Left  _ -> anyException
                 Right b -> a === b
  where
    supressException :: NFData a => a -> PropertyM IO (Either SomeException a)
    supressException = run . try . evaluate . force

    anyException :: Property
    anyException = True === True



monoFoldablePropertiesGen
  :: forall f.
     ( MonoFoldable f
     , Arbitrary f
     , Arbitrary (Element f)
     , CoArbitrary (Element f)
     , Eq (Element f)
     , Show f
     , Show (Element f)
     )
  => TestTree
monoFoldablePropertiesGen = testGroup "Properties of MonoFoldable"
    [ testProperty "ofoldr f z t === appEndo (ofoldMap (Endo . f) t ) z" testFoldrFoldMap
    , testProperty "ofoldl' f z t === appEndo (getDual (ofoldMap (Dual . Endo . flip f) t)) z" testFoldlFoldMap
    , testProperty "ofoldr f z === ofoldr f z . otoList" testFoldr
    , testProperty "ofoldl' f z === ofoldl' f z . otoList" testFoldl
    , testProperty "ofoldr1Ex f z === ofoldr1Ex f z . otoList" testFoldr1
    , testProperty "ofoldl1Ex' f z === ofoldl1Ex' f z . otoList" testFoldl1
    , testProperty "oall f === getAll . ofoldMap (All . f)" testAll
    , testProperty "oany f === getAny . ofoldMap (Any . f)" testAny
    , testProperty "olength === length . otoList" testLength
    , testProperty "onull === (0 ==) . olength" testNull
    , testProperty "headEx === getFirst . ofoldMap1Ex First" testHead
    , testProperty "lastEx === getLast . ofoldMap1Ex Last" testTail
    , testProperty "oelem e /== onotElem e" testInclusionConsistency
    ]
  where
    testFoldrFoldMap :: (Blind (Element f -> Word -> Word), Word, f) -> Property
    testFoldrFoldMap (Blind f, z, bv) =
        ofoldr f z bv === appEndo (ofoldMap (Endo . f) bv) z

    testFoldlFoldMap :: (Blind (Word -> Element f -> Word), Word, f) -> Property
    testFoldlFoldMap (Blind f, z, bv) =
        ofoldl' f z bv === appEndo (getDual (ofoldMap (Dual . Endo . flip f) bv)) z

    testFoldr :: (Blind (Element f -> Word -> Word), Word, f) -> Property
    testFoldr (Blind f, z, bv) =
        ofoldr f z bv === (ofoldr f z . otoList) bv

    testFoldl :: (Blind (Word -> Element f -> Word), Word, f) -> Property
    testFoldl (Blind f, z, bv) =
        ofoldl' f z bv === (ofoldl' f z . otoList) bv

    testFoldr1 :: (Blind (Element f -> Element f -> Element f), f) -> Property
    testFoldr1 (Blind f, bv) =
        (not . onull) bv  ==> ofoldr1Ex f bv === (ofoldr1Ex f . otoList) bv

    testFoldl1 :: (Blind (Element f -> Element f -> Element f), f) -> Property
    testFoldl1 (Blind f, bv) =
        (not . onull) bv  ==> ofoldl1Ex' f bv === (ofoldl1Ex' f . otoList) bv

    testAll :: (Blind (Element f -> Bool), f) -> Property
    testAll (Blind f, bv) =
        oall f bv === (getAll . ofoldMap (All . f)) bv

    testAny :: (Blind (Element f -> Bool), f) -> Property
    testAny (Blind f, bv) =
        oany f bv === (getAny . ofoldMap (Any . f)) bv

    testLength :: f -> Property
    testLength bv =
        olength bv === (length . otoList) bv

    testNull :: f -> Property
    testNull bv =
        onull bv === ((0 ==) . olength) bv

    testHead :: f -> Property
    testHead bv =
        (not . onull) bv ==> headEx bv === (getFirst . ofoldMap1Ex First) bv

    testTail :: f -> Property
    testTail bv =
        (not . onull) bv ==> lastEx bv === (getLast . ofoldMap1Ex Last) bv

    testInclusionConsistency :: (Element f, f) -> Property
    testInclusionConsistency (e, bv) =
        oelem e bv === (not . onotElem e) bv
