-----------------------------------------------------------------------------
-- |
-- Module      :  Analysis.Parsimony.Dynamic.DirectOptimization.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Sankoff character analysis (cost and median)
--
-- This only works on static characters, and due to the traversal, only one
-- character will be received at a time.
--
-- Assumes binary trees.
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts #-}

module Analysis.Parsimony.Dynamic.DirectOptimization.Internal where

import           Analysis.Parsimony.Dynamic.DirectOptimization.Pairwise
import           Bio.Character.Decoration.Dynamic
import           Bio.Character.Encodable
import           Control.Lens
import           Data.IntMap        (IntMap)
import qualified Data.IntMap as IM
import           Data.Key    hiding ((!))
import           Data.List.NonEmpty (NonEmpty( (:|) ))
import           Data.Monoid
import           Data.MonoTraversable 
import           Data.Word
import           Prelude     hiding (lookup, zip)


type PairwiseAlignment s = s -> s -> (s, Double, s, s, s)


directOptimizationPostOrder
  :: SimpleDynamicDecoration d c
  => PairwiseAlignment c
  -> d
  -> [DynamicDecorationDirectOptimizationPostOrderResult c]
  ->  DynamicDecorationDirectOptimizationPostOrderResult c
directOptimizationPostOrder pairwiseAlignment charDecoration xs =
    case xs of
        []   -> initializeLeaf charDecoration
        y:ys -> updateFromLeaves pairwiseAlignment $ y:|ys


initializeLeaf
  :: SimpleDynamicDecoration d c
  => d
  -> DynamicDecorationDirectOptimizationPostOrderResult c
initializeLeaf = extendDynamicToPostOrder <$> id <*> const 0 <*> (^. encoded) <*> (^. encoded) <*> (^. encoded) <*> (^. encoded)


updateFromLeaves
  :: EncodableDynamicCharacter c
  => PairwiseAlignment c
  -> NonEmpty (DynamicDecorationDirectOptimizationPostOrderResult c)
  -> DynamicDecorationDirectOptimizationPostOrderResult c
updateFromLeaves _ (x:|[]) = x
updateFromLeaves pairwiseAlignment (leftChild:|rightChild:_) =
    extendDynamicToPostOrder leftChild (truncate cost) ungapped gapped lhsAlignment rhsAlignment
  where
    -- TODO:
    -- Change type of 'cost' to an integral value like 'Word'
    (ungapped, cost, gapped, lhsAlignment, rhsAlignment) = pairwiseAlignment (leftChild ^. encoded) (rightChild ^. encoded)


directOptimizationPreOrder
  :: DirectOptimizationPostOrderDecoration d c
  => PairwiseAlignment c
  -> d
  -> [(Word, DynamicDecorationDirectOptimization c)]
  ->  DynamicDecorationDirectOptimization c
directOptimizationPreOrder pairwiseAlignment charDecoration xs =
    case xs of
        []            -> initializeRoot charDecoration
        (_, parent):_ -> updateFromParent pairwiseAlignment charDecoration parent


initializeRoot
  :: DirectOptimizationPostOrderDecoration d c
  => d
  -> DynamicDecorationDirectOptimization c
initializeRoot = extendPostOrderToDirectOptimization <$> id <*> (^. preliminaryUngapped) <*> (^. preliminaryGapped)


updateFromParent
  :: (EncodableDynamicCharacter c, DirectOptimizationPostOrderDecoration d c)
  => PairwiseAlignment c
  -> d
  -> DynamicDecorationDirectOptimization c
  -> DynamicDecorationDirectOptimization c
updateFromParent pairwiseAlignment currentDecoration parentDecoration =
    extendPostOrderToDirectOptimization currentDecoration ungapped gapped
  where
    (ungapped, gapped) = tripleComparison pairwiseAlignment currentDecoration (parentDecoration ^. finalGapped)

  
-- |
-- A three way comparison of characters used in the DO preorder traversal.
tripleComparison
  :: ( EncodableDynamicCharacter c, DirectOptimizationPostOrderDecoration d c)
  => PairwiseAlignment c
  -> d
  -> c
  -> (c, c)
tripleComparison pairwiseAlignment childDecoration parentCharacter = (ungapped, gapped)
  where
    costStructure     = childDecoration ^. characterSymbolTransitionCostMatrixGenerator
    childCharacter    = childDecoration ^. preliminaryUngapped
    childLeftAligned  = childDecoration ^. leftAlignment
    childRightAligned = childDecoration ^. rightAlignment
    
    (_, _, derivedAlignment, _, childAlignment) = pairwiseAlignment parentCharacter childCharacter
    newGapIndicies         = newGapLocations childCharacter childAlignment
    extendedLeftCharacter  = insertNewGaps newGapIndicies childLeftAligned
    extendedRightCharacter = insertNewGaps newGapIndicies childRightAligned
    (_, ungapped, gapped)  = threeWayMean costStructure derivedAlignment extendedLeftCharacter extendedRightCharacter


-- |
-- Returns the indicies of the gaps that were added in the second character when
-- compared to the first character.
newGapLocations :: EncodableDynamicCharacter c => c -> c -> IntMap Int
newGapLocations originalChar newChar
  | olength originalChar == olength newChar = mempty
  | otherwise                               = newGaps
  where
    (_,_,newGaps) = ofoldl' f (otoList originalChar, 0, mempty) newChar
    gap = getGapElement $ newChar `indexStream` 0
    f (  [], i, is) e
      | e == gap  = ([], i, IM.insertWith (+) i 1 is)
      | otherwise = ([], i, is)
    f (x:xs, i, is) e
      | e == gap && x /= gap = (x:xs, i  , IM.insertWith (+) i 1 is)
      | otherwise            = (  xs, i+1, is)


-- |
-- Given a list of gap location and a character returns a longer character with
-- the supplied gaps inserted at the corersponding locations.
insertNewGaps :: EncodableDynamicCharacter c => IntMap Int -> c -> c
insertNewGaps insertionIndicies character = constructDynamic . (<> trailingGaps) . foldMapWithKey f $ otoList character
  where
    len = olength character
    gap = getGapElement $ character `indexStream` 0
    trailingGaps = maybe [] (`replicate` gap) $ len `lookup` insertionIndicies
    f i e =
      case i `lookup` insertionIndicies of
        Nothing -> [e]
        Just n  -> replicate n gap <> [e]


-- |
-- Calculates the mean character and cost between three supplied characters.
threeWayMean :: (EncodableDynamicCharacter c)
             => (Int -> Int -> Int)
             -> c -> c -> c -> (Int, c, c)
threeWayMean costStructure char1 char2 char3
  | not uniformLength = error $ "Three sequences supplied to 'threeWayMean' function did not have uniform length." -- <> show char1 <> show char2 <> show char3
  | otherwise         = (sum costValues, constructDynamic $ filter (/= gap) meanStates, constructDynamic meanStates)
  where
    gap                 = getGapElement $ char1 `indexStream` 0
    uniformLength       = olength char1 == olength char2 && olength char2 == olength char3
    (meanStates, costValues) = unzip $ zipWith3 f (otoList char1) (otoList char2) (otoList char3)
    f a b c = minimalChoice -- minimumBy (comparing snd)
            [ getOverlap a b costStructure
            , getOverlap a c costStructure
            , getOverlap b c costStructure
            ]



