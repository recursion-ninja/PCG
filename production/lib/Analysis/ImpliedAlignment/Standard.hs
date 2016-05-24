-----------------------------------------------------------------------------
-- |
-- Module      :  Analysis.ImpliedAlignment.Standard
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Standard algorithm for implied alignment
-----------------------------------------------------------------------------

-- TODO: Make an AppliedAlignment.hs file for exposure of appropriate functions

module Analysis.ImpliedAlignment.Standard where

import Analysis.ImpliedAlignment.Internal
import Analysis.Parsimony.Binary.DirectOptimization
import Bio.Metadata
import Bio.PhyloGraph.DAG
import Bio.PhyloGraph.Forest
import Bio.PhyloGraph.Network
import Bio.PhyloGraph.Node
import Bio.PhyloGraph.Solution
import Bio.PhyloGraph.Tree hiding (code)
import Bio.Character.Dynamic.Coded

import Data.BitVector      hiding (foldr, replicate, foldl)
import Data.IntMap                (IntMap, assocs, insert)
import qualified Data.IntMap as IM
import Data.IntSet (IntSet)
import qualified Data.IntSet as IS
import Data.Maybe
import Data.Monoid
import Data.MonoTraversable
import Data.Vector                (Vector, (!), (//), filter, foldr, generate, imap, replicate, unzip3, zipWith, zipWith3, zipWith4)
import qualified Data.Vector as V
import Prelude             hiding (filter, foldr, lookup, replicate, unzip3, zip3, zipWith, zipWith3, foldl)

import Debug.Trace

-- | Top level wrapper to do an IA over an entire solution
-- takes a solution
-- returns an AlignmentSolution
iaSolution :: SolutionConstraint r m f t n e s => r -> AlignmentSolution s
iaSolution inSolution | trace ("iaSolution " ++ show inSolution) False = undefined
iaSolution inSolution = fmap (flip iaForest (getMetadata inSolution)) (getForests inSolution)

-- | Simple wrapper to do an IA over a forest
-- takes in a forest and some metadata
-- returns an alignment forest
iaForest :: (ForestConstraint f t n e s, Metadata m s) => f -> Vector m -> AlignmentForest s
iaForest inForest inMeta = fmap (flip impliedAlign inMeta) (trees inForest)

-- TODO: used concrete BitVector type instead of something more appropriate, like EncodableDynamicCharacter. 
-- This also means that there are a bunch of places below that could be using EDC class methods that are no longer.
-- The same will be true in DO.
-- | Function to perform an implied alignment on all the leaves of a tree
-- takes a tree and some metadata
-- returns an alignment object (an intmap from the leaf codes to the aligned sequence)
-- TODO: Consider building the alignment at each step of a postorder rather than grabbing wholesale
impliedAlign :: (TreeConstraint t n e s, Metadata m s) => t -> Vector m -> Alignment s
--impliedAlign inTree inMeta | trace ("impliedAlign with tree " ++ show inTree) False = undefined
impliedAlign inTree inMeta = foldr (\n acc -> insert (getCode n) (makeAlignment n lens) acc) mempty allLeaves
    where
        (lens, curTree) = numeratePreorder inTree (getRoot inTree) inMeta (replicate (length inMeta) 0)
        allLeaves = filter (flip nodeIsLeaf curTree) (getNodes curTree)

-- | Simple function to generate an alignment from a numerated node
-- Takes in a Node
-- returns a vector of characters
makeAlignment :: (NodeConstraint n s) => n -> Counts -> Vector s
makeAlignment n seqLens = makeAlign (getFinalGapped n) (getHomologies n)
    where
        -- onePos :: s -> Homologies -> Int -> Int -> Int -> s
        onePos c h l sPos hPos 
            | sPos > l - 1 = emptyLike c
            | h ! hPos == sPos = unsafeCons (grabSubChar c (h ! hPos)) (onePos c h l (sPos + 1) (hPos + 1))
            | otherwise = unsafeCons (gapChar c) (onePos c h l (sPos + 1) hPos)
        -- makeOne :: s -> Homologies -> Int -> s
        makeOne char homolog len = onePos char homolog len 0 0
        --makeAlign :: Vector s -> HomologyTrace -> Vector s
        makeAlign dynChar homologies = zipWith3 makeOne dynChar homologies seqLens

-- | Main recursive function that assigns homology traces to every node
-- takes in a tree, a current node, a vector of metadata, and a vector of counters
-- outputs a resulting vector of counters and a tree with the assignments
-- TODO: something seems off about doing the DO twice here
numeratePreorder :: (TreeConstraint t n e s, Metadata m s) => t -> n -> Vector m -> Counts -> (Counts, t)
--numeratePreorder _ curNode _ _ | trace ("numeratePreorder at " ++ show curNode) False = undefined
numeratePreorder inTree curNode inMeta curCounts
    | nodeIsRoot curNode inTree = (curCounts, inTree `update` [setHomologies curNode defaultHomologs])
    | isLeafNode = (curCounts, inTree)
    | leftOnly =
        let
            (leftChildHomolog, counterLeft, insertionEvents) = numerateNode curNode (fromJust $ leftChild curNode inTree) curCounts inMeta
            backPropagatedTree                               = backPropagation inTree leftChildHomolog insertionEvents
            editedTreeLeft                                   = backPropagatedTree `update` [leftChildHomolog]
            (leftRecurseCount, leftRecurseTree)              = numeratePreorder editedTreeLeft leftChildHomolog inMeta counterLeft
        in (leftRecurseCount, leftRecurseTree)
    | rightOnly =
        let
            (rightChildHomolog, counterRight, insertionEvents) = numerateNode curNode (fromJust $ rightChild curNode inTree) curCounts inMeta
            backPropagatedTree                                 = backPropagation inTree rightChildHomolog insertionEvents
            editedTreeRight                                    = backPropagatedTree `update` [rightChildHomolog]
            (rightRecurseCount, rightRecurseTree)              = numeratePreorder editedTreeRight rightChildHomolog inMeta counterRight
        in (rightRecurseCount, rightRecurseTree)
    | otherwise =
        let
            -- TODO: should I switch the order of align and numerate? probs
            ( leftChildHomolog, counterLeft , insertionEventsLeft)  = numerateNode curNode (fromJust $ leftChild curNode inTree) curCounts inMeta
            backPropagatedTree                                      = backPropagation inTree leftChildHomolog insertionEventsLeft
            (leftRecurseCount, leftRecurseTree)                     = numeratePreorder backPropagatedTree leftChildHomolog inMeta counterLeft
            leftRectifiedTree                                       = leftRecurseTree `update` [leftChildHomolog]
            
            curNode'                                                = leftRectifiedTree `getNthNode` (getCode curNode)
            (rightChildHomolog, counterRight, insertionEventsRight) = numerateNode curNode' (fromJust $ rightChild curNode' leftRectifiedTree) leftRecurseCount inMeta
            backPropagatedTree'                                     = backPropagation leftRectifiedTree rightChildHomolog insertionEventsRight
            rightRectifiedTree                                      = backPropagatedTree' `update` [rightChildHomolog]
            -- TODO: need another align and assign between the left and right as a last step?
            output                                                  = numeratePreorder rightRectifiedTree rightChildHomolog inMeta counterRight
        in output

        where
            curSeqs = getFinalGapped curNode
            isLeafNode = leftOnly && rightOnly
            leftOnly   = isNothing $ rightChild curNode inTree
            rightOnly  = isNothing $ leftChild curNode inTree
            -- TODO: check if this is really the default
            defaultHomologs = imap (\i _ -> generate (numChars (curSeqs ! i)) (+ 1)) inMeta

            -- Simple wrapper to align and assign using DO
            --alignAndAssign :: NodeConstraint n s => n -> n -> (n, n)
            -- TODO: Don't use the gapped here
{-
            alignAndAssign node1 node2 = (setFinalGapped (fst allUnzip) node1, setFinalGapped (snd allUnzip) node2)
                where
                    allUnzip = unzip allDO
                    allDO = zipWith3 doOne (getFinalGapped node1) (getFinalGapped node2) inMeta
                    doOne s1 s2 m = (gapped1, gapped2)
                        where (_, _, _, gapped1, gapped2) = naiveDO s1 s2 m
-}


backPropagation :: TreeConstraint t n e s  => t -> n -> Vector IntSet -> t
backPropagation tree node insertionEvents = undefined {-
  | all onull insertionEvents = tree -- nothing to do thank god!
  | otherwise =
  where
    myParent  = getParent node tree
    wasIRight = getCode <$> rightChild myParent tree == Just (getCode node)
-}  

-- | Function to do a numeration on an entire node
-- given the ancestor node, ancestor node, current counter vector, and vector of metadata
-- returns a tuple with the node with homologies incorporated, and a returned vector of counters
numerateNode :: (NodeConstraint n s, Metadata m s) => n -> n -> Counts -> Vector m -> (n, Counts, Vector IntSet) 
numerateNode ancestorNode childNode initCounters inMeta = (setHomologies childNode homologs, counts, insertionEvents)
        where
            numeration = zipWith4 numerateForReals (getFinalGapped ancestorNode) (getFinalGapped childNode) (getHomologies ancestorNode) initCounters 
            (homologs, counts, insertionEvents) = unzip3 numeration
            generateGapChar m = setBit (bitVec 0 (0 :: Integer)) (length (getAlphabet m) - 1)

{-
-- | Function to do a numeration on one character at a node
-- given the ancestor sequence, ancestor homologies, child sequence, and current counter for position matching
-- returns a tuple of the Homologies vector and an integer count
numerateOne :: (SeqConstraint s) => BitVector -> s -> Homologies -> s -> Int -> (Homologies, Int)
--numerateOne _ a h c _ | trace ("numerateOne with ancestor " ++ show a ++ " and child " ++ show c ++ " and homologies " ++ show h) False = undefined
numerateOne gapCharacter ancestorSeq ancestorHomologies childSeq initCounter = foldl (determineHomology gapCharacter) (mempty, initCounter) foldIn
    where
        getAllSubs s = foldr (\p acc -> grabSubChar s p `cons` acc) mempty (fromList [0..(numChars s) - 1])
        -- TODO: verify that ancestorHomologies has the correct length as the allSubs
        foldIn = --trace ("calls to homology " ++ show (getAllSubs childSeq) ++ show (getAllSubs ancestorSeq)) $
                    zip3 (getAllSubs childSeq) (getAllSubs ancestorSeq) ancestorHomologies

-- Finds the homology position between any two characters
determineHomology :: BitVector -> (Homologies, Int) -> (BitVector, BitVector, Int) -> (Homologies, Int)
--determineHomology _ i (c, a, h) | trace ("one homology " ++ show i ++ " on " ++ show (c, a, h)) False = undefined
determineHomology gapCharacter (homologSoFar, counterSoFar) (childChar, ancestorChar, ancestorHomolog)
    | ancestorChar == gapCharacter = (homologSoFar V.++ pure counterSoFar, counterSoFar    )
    | childChar    /= gapCharacter = (homologSoFar V.++ pure ancestorHomolog, counterSoFar + 1)
    | otherwise                    = (homologSoFar V.++ pure counterSoFar, counterSoFar + 1) --TODO: check this case
-}

-- | Function to do a numeration on one character at a node
-- given the ancestor sequence, ancestor homologies, child sequence, and current counter for position matching
-- returns a tuple of the Homologies vector and an integer count
{-
numerateOne :: (SeqConstraint s) => BitVector -> s -> Homologies -> s -> Int -> (Homologies, Int)
numerateOne = numerateOne' {-(h, c)
        where 
            (h, c, _, _) = determineHomology (mempty, initCounter, 0, 0, 0)

            -- | Find the homology at two positions
            determineHomology :: (Homologies, Int, Int, Int, Int) -> (Homologies, Int, Int, Int, Int)
            determineHomology cur@(homologSoFar, counter, i, j, k) 
                | isNothing aChar || isNothing cChar = cur
                | (fromJust aChar) == gapCharacter = determineHomology (homologSoFar V.++ pure counter, counter + 1, i + 1, j + 1, k)
                | (fromJust cChar) /= gapCharacter = determineHomology (homologSoFar V.++ pure (aHomologies V.! hPos), pCount, cPos + 1, hPos + 1)
                | otherwise                        = determineHomology (homologSoFar, pCount, cPos, hPos + 1) 
                    where
                        aChar = safeGrab aSeq i
                        cChar = safeGrab cSeq i-}
-}          

type Counter = Int
newtype MutationAccumulator = Accum (IntMap Int, Counter, Int, Int, Int, IntSet)

{-
-- Do as Ward says (in his paper) not as he does (in POY psuedocode)..?
-- TODO: _REALLY_ make sure that this is correct!
numerateOne' :: (SeqConstraint s) => BitVector -> s -> Homologies -> s -> Counter -> (Homologies, Int)
numerateOne' _gap aSeq aHomologies cSeq initialCounter = (aHomologies // assocs mutations, counter')
  where
    (Accum (mutations, counter', _, _, _)) = ofoldl' f (Accum (mempty, initialCounter, 0, 0, 0)) cSeq
    gapCharacter = gapChar cSeq
    f (Accum (changeSet, counter, i, j, k)) _ -- Ignore the element parameter because the compiler can't make the logical type deduction :(
      | ancestorCharacter == gapCharacter = Accum (insert i counter           changeSet, counter + 1, i + 1, j + 1, k    )
      | childCharacter    /= gapCharacter = Accum (insert j ancestorReference changeSet, counter    , i + 1, j + 1, k + 1)
      | otherwise                         = Accum (                           changeSet, counter    , i + 1, j    , k + 1)
      where
        childCharacter    = fromJust $ safeGrab cSeq i
        ancestorCharacter = fromJust $ safeGrab aSeq i 
        ancestorReference = aHomologies ! k 


-- Trying to do as Andres does not as he says

data Align = Insertion | Deletion | Missing

numerateOne'' :: (SeqConstraint s) => BitVector -> s -> s -> Int -> Vector (Int, BitVector, Int, Align, Int) -> Vector (Int, BitVector, Int, Align, Int)
numerateOne'' ourGap seq1 seq2 i 
    | isNothing aChar || isNothing bChar = undefined
        where
            aChar = safeGrab seq1 i 
            bChar = safeGrab seq2 i
-}

numerateForReals :: SeqConstraint s => s -> s -> Homologies -> Counter -> (Homologies, Counter, IntSet)
numerateForReals ancestorSeq descendantSeq ancestorHomologies initialCounter = (descendantHomologies, counter', insertionEvents)
  where
    gapCharacter = gapChar descendantSeq

    descendantHomologies = V.generate (olength descendantSeq) g
     where
       g :: Int -> Int
       g i =
         case i `IM.lookup` mapping of
           Nothing -> error "The aparently not impossible happened!"
           Just v  -> v

    (Accum (mapping, counter', _, _, _, insertionEvents)) = ofoldl' f (Accum (mempty, initialCounter, 0, 0, 0, mempty)) descendantSeq
      where
        f (Accum (indexMapping, counter, i, ancestorOffset, childOffset, insertionEventIndicies)) _ -- Ignore the element parameter because the compiler can't make the logical type deduction :(
          -- Biological "Nothing" case
          | ancestorCharacter == gapCharacter && descendantCharacter == gapCharacter = Accum (insert i (i + childOffset    ) indexMapping, counter    , i + 1, ancestorOffset    , childOffset    , insertionEventIndicies)
          -- Biological deletion event case
          | ancestorCharacter /= gapCharacter && descendantCharacter == gapCharacter = Accum (insert i (i + childOffset + 1) indexMapping, counter + 1, i + 1, ancestorOffset    , childOffset + 1, insertionEventIndicies)
          -- Biological insertion event case
          | ancestorCharacter == gapCharacter && descendantCharacter /= gapCharacter = Accum (insert i (i + childOffset    ) indexMapping, counter + 1, i + 1, ancestorOffset + 1, childOffset    , (i + childOffset) `IS.insert` insertionEventIndicies)
          -- Biological substitution or non-substitution case
          | otherwise {- Both not gap -}                                             = Accum (insert i (i + childOffset)     indexMapping, counter    , i + 1, ancestorOffset    , childOffset    , insertionEventIndicies)
          where
--          j = i + childOffset
            descendantCharacter    = fromJust $ safeGrab descendantSeq i
            ancestorCharacter = fromJust $ safeGrab ancestorSeq   i 
--          ancestorReference = ancestorHomologies ! (i + ancestorOffset)

