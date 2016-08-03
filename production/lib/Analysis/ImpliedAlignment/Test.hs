-----------------------------------------------------------------------------
-- |
-- Module      :  Analysis.ImpliedAlignment.Test
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Unit tests for implied alignment
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleInstances, TypeSynonymInstances #-}

module Analysis.ImpliedAlignment.Test where

import           Analysis.Parsimony.Binary.Internal
import           Analysis.Parsimony.Binary.Optimization
import           Analysis.Parsimony.Binary.DirectOptimization
import           Analysis.ImpliedAlignment.DynamicProgramming
import           Analysis.ImpliedAlignment.Internal
import           Analysis.ImpliedAlignment.Standard
import           Analysis.ImpliedAlignment.Test.Trees
import           Bio.Character.Dynamic.Coded
import           Bio.Character.Parsed
import           Bio.Metadata
import           Bio.PhyloGraph            hiding (name)
import           Bio.PhyloGraph.Network           (nodeIsLeaf)
import           Bio.PhyloGraph.Node.ImpliedAlign (getHomologies')
import           Data.Alphabet
import           Data.BitVector          (BitVector, setBit, bitVec)
import           Data.Foldable
import           Data.Function           (on)
import qualified Data.IntMap       as IM
import           Data.IntSet             (IntSet)
import           Data.List
import           Data.MonoTraversable
import qualified Data.Set          as S
import           Data.Vector             (Vector)
import qualified Data.Vector       as V
import           Test.Custom
--import qualified Test.Custom.Types as T
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck
import           Test.QuickCheck.Arbitrary.Instances

import Debug.Trace

testSuite :: TestTree
testSuite = testGroup "Implied Alignment"
          [ testNumerate
          , testImpliedAlignmentCases
--          , fullIA
          ]

fullIA :: TestTree
fullIA = testGroup "Full alignment properties"
    [ lenHoldsTest
    ]
  where
    lenHoldsTest = testProperty "The sequences on a tree are longer or the same at end." checkLen

    checkLen :: SimpleTree -> Bool
    checkLen inputTree = nodeInvariantHolds impliedAlignmentLengthIsLonger outputTree
      where
        outputTree = performImpliedAlignment inputTree
        impliedAlignmentLengthIsLonger node = and $ V.zipWith ((<=) `on` olength) nodeImpliedAlignements nodeFinalCharacters
          where
            nodeImpliedAlignements = getHomologies' node
            nodeFinalCharacters    = getFinalGapped node

testNumerate :: TestTree
testNumerate = testGroup "Numeration properties"
      [ idHolds
      , lengthHolds
      , counterIncrease
      , monotonic
      ]
    where
        idHolds                          = testProperty "When a sequence is numerated with itself, get indices and the same counter" checkID
        checkID :: DynamicChar -> Bool
        checkID inChar                   = onull inChar || (traces == defaultH && counter <= olength inChar)
            where
                defaultH = V.fromList [0..olength inChar - 1] 
                (traces, (_, counter), _) =  numerateOne inChar inChar (0, 0)

        -- TODO: Talk to Eric about olength ()
        lengthHolds                      = testProperty "Numerate returns a sequence of the correct length" checkLen
        checkLen :: (GoodParsedChar, GoodParsedChar) -> Int -> Bool
        checkLen inParse count           = V.length traces >= maxLen
            where 
                (seq1, seq2)              = encodeArbSameLen inParse
                (traces, (_, counter), _) = numerateOne seq1 seq2 (olength seq1, count)
                maxLen                    = maximum [olength seq1, olength seq2]

        counterIncrease                   = testProperty "After numerate runs, counter is same or larger" checkCounter
        checkCounter :: (GoodParsedChar, GoodParsedChar) -> Int -> Bool
        checkCounter inParse count        = counter >= count
            where 
                (seq1, seq2)              = encodeArbSameLen inParse
                (traces, (_, counter), _) = numerateOne seq1 seq2 (olength seq1, count)
        monotonic = testProperty "Numerate produces a monotonically increasing homology" checkIncrease
        checkIncrease :: (GoodParsedChar, GoodParsedChar) -> Int -> Bool
        checkIncrease inParse count       = increases $ toList traces
            where 
                (seq1, seq2)         = encodeArbSameLen inParse
                (traces, counter, _) = numerateOne seq1 seq2 (olength seq1, count)
                increases :: Ord a => [a] -> Bool
                increases []         = True
                increases [x]        = True
                increases (x:y:xs)   = x < y && increases (y:xs)

-- | Useful function to convert encoding information to two encoded seqs
encodeArbSameLen :: (GoodParsedChar, GoodParsedChar) -> (DynamicChar, DynamicChar)
encodeArbSameLen (parse1, parse2) = (encodeDynamic alph (V.take minLen p1), encodeDynamic alph (V.take minLen p2))
    where
        (p1,p2) = (getGoodness parse1, getGoodness parse2)
        minLen  = minimum [length p1, length p2]
        oneAlph = foldMap S.fromList
        alph    = constructAlphabet $ oneAlph p1 `S.union` oneAlph p2

-- | Newtyping ensures that the sequence and ambiguity groups are both non empty.
newtype GoodParsedChar
      = GoodParsedChar
      { getGoodness :: ParsedChar
      } deriving (Eq,Show)

instance Arbitrary GoodParsedChar where
  arbitrary = do
    symbols                     <- getNonEmpty <$> arbitrary :: Gen [String]
    let ambiguityGroupGenerator =  sublistOf symbols `suchThat` (not . null)
    someAmbiguityGroups         <- V.fromList <$> listOf1 ambiguityGroupGenerator
    pure $ GoodParsedChar someAmbiguityGroups



insertionDeletionTest :: Foldable t
                      => Int          -- ^ Root node reference
                      -> String       -- ^ Alphabet symbols
                      -> t (Int, String, [Int])
                      -> Int          -- ^ Parent node index
                      -> Int          -- ^ Child  node index
                      -> [Int]        -- ^ deletion events
                      -> [(Int, Int)] -- ^ Insertion events
                      -> Assertion
insertionDeletionTest rootRef symbols spec parentRef childRef expectedDeletions expectedInsertions = undefined
  where
    inputTree  = createSimpleTree rootRef symbols spec
    outputTree = allOptimization 1 defMeta inputTree
