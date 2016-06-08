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

{-# LANGUAGE AllowAmbiguousTypes, TypeFamilies #-}

-- TODO: Make an AppliedAlignment.hs file for exposure of appropriate functions

module Analysis.ImpliedAlignment.Standard where

import           Analysis.General.NeedlemanWunsch hiding (SeqConstraint)
import           Analysis.ImpliedAlignment.Internal
import           Analysis.Parsimony.Binary.Internal (allOptimization)
import           Bio.Metadata
import           Bio.PhyloGraph.DAG    hiding (code, root)
import           Bio.PhyloGraph.Forest
import           Bio.PhyloGraph.Network
import           Bio.PhyloGraph.Node   hiding (children, code, name)
import           Bio.PhyloGraph.Solution
import           Bio.PhyloGraph.Tree
import           Bio.Character.Dynamic.Coded
import           Control.Applicative          ((<|>))
import           Data.Alphabet
import           Data.BitMatrix
import           Data.Foldable
import           Data.IntMap                  (IntMap, insert)
import qualified Data.IntMap            as IM
import           Data.IntSet                  (IntSet)
import qualified Data.IntSet            as IS
import           Data.Key
import           Data.Matrix.NotStupid hiding ((<|>),toList)
import           Data.Maybe
import           Data.Monoid
import           Data.MonoTraversable
import           Data.Vector                  (Vector, imap)
import qualified Data.Vector             as V
import           Prelude               hiding (lookup)
--import           Debug.Trace
import           Test.Custom.Tree

defMeta :: Vector (CharacterMetadata s)
defMeta = pure CharMeta
        { charType   = DirectOptimization
        , alphabet   = constructAlphabet []
        , name       = "DefaultCharacter"
        , isAligned  = False
        , isIgnored  = False
        , weight     = 1.0
        , stateNames = mempty
        , fitchMasks = undefined
        , rootCost   = 0.0
        , costs      = GeneralCost { indelCost = 1, subCost = 1 }
        }
  
newtype MutationAccumulator = Accum (IntMap Int, Int, Int, Int, Int, IntSet)

-- | Top level wrapper to do an IA over an entire solution
-- takes a solution
-- returns an AlignmentSolution
iaSolution :: SolutionConstraint r m f t n e s => r -> AlignmentSolution s
--iaSolution inSolution | trace ("iaSolution " ++ show inSolution) False = undefined
iaSolution inSolution = fmap (`iaForest` getMetadata inSolution) (getForests inSolution)

-- | Simple wrapper to do an IA over a forest
-- takes in a forest and some metadata
-- returns an alignment forest
iaForest :: (ForestConstraint f t n e s, Metadata m s) => f -> Vector m -> AlignmentForest s
--iaForest inForest inMeta | trace ("iaForest ")  False = undefined
iaForest inForest inMeta = fmap (`impliedAlign` inMeta) (trees inForest)

-- TODO: used concrete BitVector type instead of something more appropriate, like EncodableDynamicCharacter. 
-- This also means that there are a bunch of places below that could be using EDC class methods that are no longer.
-- The same will be true in DO.
-- | Function to perform an implied alignment on all the leaves of a tree
-- takes a tree and some metadata
-- returns an alignment object (an intmap from the leaf codes to the aligned sequence)
-- TODO: Consider building the alignment at each step of a postorder rather than grabbing wholesale
impliedAlign :: (TreeConstraint t n e s, Metadata m s) => t -> Vector m -> Alignment s
--impliedAlign inTree inMeta | trace ("impliedAlign with tree " ++ show inTree) False = undefined
impliedAlign inTree inMeta = extractAlign numerated inMeta
    where
        numerated = numeratePreorder inTree (root inTree) inMeta (V.replicate (length inMeta) (0, 0))

extractAlign :: (TreeConstraint t n e s, Metadata m s) => (Counts, t) -> Vector m -> Alignment s
--extractAlign (lens, numeratedTree) inMeta | trace ("extract alignments " ++ show numeratedTree) False = undefined
extractAlign (lens, numeratedTree) _inMeta = foldr (\n acc -> insert (fromJust $ code n numeratedTree) (makeAlignment n lens) acc) mempty allLeaves
    where
      allLeaves = filter (`nodeIsLeaf` numeratedTree) allNodes
      allNodes  = getNthNode numeratedTree <$> [0..numNodes numeratedTree -1]
      
-- | Simple function to generate an alignment from a numerated node
-- Takes in a Node
-- returns a vector of characters
makeAlignment :: (NodeConstraint n s) => n -> Counts -> Vector s
--makeAlignment n seqLens | trace ("make alignment on n " ++ show n ++ " with lens " ++ show seqLens) False = undefined
makeAlignment n seqLens = makeAlign (getFinalGapped n) (getHomologies n)
    where
        --makeAlign :: Vector s -> HomologyTrace -> Vector s
        makeAlign dynChar homologies = V.zipWith3 makeOne' dynChar homologies seqLens
        -- | /O((n+m)*log(n)), could be linear, but at least it terminates!
        makeOne' char homolog len = fromChars . toList $ result
          where
            result = V.generate (fst len + snd len) f
              where
                f i = case i `IM.lookup` mapping of
                        Nothing -> gapChar char
                        Just j  -> char `grabSubChar` j
                mapping = V.ifoldl' (\im k v -> IM.insert v k im) mempty homolog

-- | Main recursive function that assigns homology traces to every node
-- takes in a tree, a current node, a vector of metadata, and a vector of counters
-- outputs a resulting vector of counters and a tree with the assignments
-- TODO: something seems off about doing the DO twice here
numeratePreorder :: (TreeConstraint t n e s, Metadata m s) => t -> n -> Vector m -> Counts -> (Counts, t)
--numeratePreorder initTree curNode _ _ | trace ("numeratePreorder at " ++ show initTree) False = undefined
numeratePreorder initTree initNode inMeta curCounts
    | isLeafNode =  (curCounts, inTree)
    | leftOnly = --trace "left only case" $
        let
            (leftChildHomolog, counterLeft, insertionEvents) = alignAndNumerate curNode (fromJust $ leftChild curNode inTree) curCounts inMeta
            editedTreeLeft                                   = propagateIt inTree leftChildHomolog insertionEvents
            (leftRecurseCount, leftRecurseTree)              = numeratePreorder editedTreeLeft leftChildHomolog inMeta counterLeft
        in (leftRecurseCount, leftRecurseTree)
    | rightOnly = --trace "right only case" $
        let
            (rightChildHomolog, counterRight, insertionEvents) = alignAndNumerate curNode (fromJust $ rightChild curNode inTree) curCounts inMeta
            editedTreeRight                                    = propagateIt inTree rightChildHomolog insertionEvents
            (rightRecurseCount, rightRecurseTree)              = numeratePreorder editedTreeRight rightChildHomolog inMeta counterRight
        in (rightRecurseCount, rightRecurseTree)
    | otherwise = --trace "two children case" $
        let
            ( leftChildHomolog, counterLeft , insertionEventsLeft)  = alignAndNumerate curNode (fromJust $ leftChild curNode inTree) curCounts inMeta
            backPropagatedTree                                      = backPropagation inTree leftChildHomolog insertionEventsLeft
            (leftRecurseCount, leftRecurseTree)                     = numeratePreorder backPropagatedTree leftChildHomolog inMeta counterLeft
            leftRectifiedTree                                       = leftRecurseTree `update` [leftChildHomolog] -- TODO: Check this order
            
            curNode'                                                = leftRectifiedTree `getNthNode` fromJust (code curNode leftRectifiedTree)
            {-(alignedRCur, alignedRight)                             = alignAndAssign curNode' (fromJust $ rightChild curNode' leftRectifiedTree)
            (rightChildHomolog, counterRight, insertionEventsRight) = numerateNode alignedRCur alignedRight leftRecurseCount inMeta-}
            (rightChildHomolog, counterRight, insertionEventsRight) = alignAndNumerate curNode' (fromJust $ rightChild curNode' leftRectifiedTree) counterLeft inMeta
            backPropagatedTree'                                     = backPropagation leftRectifiedTree rightChildHomolog insertionEventsRight
            rightRectifiedTree                                      = backPropagatedTree' `update` [rightChildHomolog]
            -- TODO: need another align and assign between the left and right as a last step?
            output                                                  = numeratePreorder rightRectifiedTree rightChildHomolog inMeta counterRight
        in output

        where
            -- Deal with the root case by making sure it gets default homologies
            inTree = if   nodeIsRoot initNode initTree
                     then initTree `update` [setHomologies initNode defaultHomologs]
                     else initTree
            curNode = getNthNode inTree . fromJust $ code initNode inTree
            curSeqs = getForAlign curNode
            isLeafNode = leftOnly && rightOnly
            leftOnly   = isNothing $ rightChild curNode inTree
            rightOnly  = isNothing $ leftChild curNode inTree
            defaultHomologs = if V.length curSeqs == 0 then V.replicate (V.length inMeta) mempty --trace ("defaultHomologs " ++ show (V.length inMeta) ++ show (V.length curSeqs))
                                else imap (\i _ -> V.enumFromN 0 (numChars (curSeqs V.! i))) inMeta
            propagateIt tree child events = tree' `update` [child]
                                            where tree' = backPropagation tree child events
            alignAndNumerate n1 n2 = {-trace ("alignment result " ++ show n1Align) $-} numerateNode n1Align n2Align
                                                where (n1Align, n2Align) = alignAndAssign n1 n2

            -- Simple wrapper to align and assign using DO
            --alignAndAssign :: NodeConstraint n s => n -> n -> (n, n)

            alignAndAssign node1 node2 = (setFinalGapped (fst allUnzip) node1, setFinalGapped (snd allUnzip) node2)
                where
                    final1 = getForAlign node1
                    final2 = getForAlign node2
                    allUnzip = V.unzip allDO
                    allDO = V.zipWith3 checkThenAlign final1 final2 inMeta
                    checkThenAlign s1 s2 m = if numChars s1 == numChars s2 then (s1, s2) else needlemanWunsch s1 s2 m

-- | Back propagation to be performed after insertion events occur in a numeration
-- goes back up and to the left, then downward
-- takes in a tree, a current node, and a vector of insertion event sets
-- return a tree with the insertion events incorporated
backPropagation :: TreeConstraint t n e s  => t -> n -> Vector IntSet -> t
--backPropagation tree node insertionEvents | trace ("backPropagation at node " ++ show (getCode node)) False = undefined
backPropagation tree node insertionEvents
  | all onull insertionEvents = tree
  | otherwise =
    case parent node tree of
      Nothing       -> tree -- If at the root, do nothing
      Just myParent -> let nodeIsLeftChild = ((\n -> fromJust $ code n tree) <$> leftChild myParent tree) == code node tree
                           (tree', _)      = accountForInsertionEventsForNode tree myParent insertionEvents
                           tree''          = if   nodeIsLeftChild -- if we are the left child, then we only have to update the current node
                                              then tree'
                                              else
                                                case leftChild myParent tree of -- otherwise we need to propagate down but not at the current node
                                                  Nothing   -> tree'
                                                  Just left -> backPropagationDownward tree' left insertionEvents
                        in backPropagation tree'' myParent insertionEvents
  where
    backPropagationDownward treeContext subTreeRoot insertionEvents' = treeContext'''
      where
        (treeContext'  , subTreeRoot'  ) = accountForInsertionEventsForNode treeContext subTreeRoot insertionEvents' -- do the current node
        treeContext'' = case  leftChild subTreeRoot' treeContext' of -- first go down and to the left
                          Nothing -> treeContext'
                          Just x  -> backPropagationDownward treeContext'  x insertionEvents'
        treeContext'''= case rightChild subTreeRoot' treeContext'' of -- then go down and to the right
                          Nothing -> treeContext''
                          Just x  -> backPropagationDownward treeContext'' x insertionEvents'
        
-- | Account for any insertion events at the current node by updating homologies
-- depends on accountForInsertionEvents to do work
-- takes in a tree, current node, and a vector of insertion event sets
-- returns an updated tree and an updated node for convenience
accountForInsertionEventsForNode :: TreeConstraint t n e s  => t -> n -> Vector IntSet -> (t, n)
accountForInsertionEventsForNode tree node insertionEvents = (tree', node')
  where
    originalHomologies = getHomologies node
    mutatedHomologies  = V.zipWith accountForInsertionEvents originalHomologies insertionEvents
    node'              = setHomologies node mutatedHomologies
    tree'              = tree `update` [node']

-- | Accounts for insertion events by mutating homology trace
-- essentially increases each homology position by the number of insertions before it
-- takes in a homologies trace and a set of insertions
-- returns a mutated homologies trace
accountForInsertionEvents :: Homologies -> IntSet -> Homologies
accountForInsertionEvents homologies insertionEvents = V.generate (length homologies) f
  where
    f i = newIndexReference
      where
        newIndexReference          = oldIndexReference + insertionEventsBeforeIndex 
        oldIndexReference          = homologies V.! i
        insertionEventsBeforeIndex = olength $ IS.filter (<= oldIndexReference) insertionEvents

-- | Function to do a numeration on an entire node
-- given the ancestor node, ancestor node, current counter vector, and vector of metadata
-- returns a tuple with the node with homologies incorporated, and a returned vector of counters
numerateNode :: (NodeConstraint n s, Metadata m s) => n -> n -> Counts -> Vector m -> (n, Counts, Vector IntSet) 
--numerateNode ancestorNode childNode initCounters _ | trace ("numerateNode on " ++ show (getCode ancestorNode) ++" and " ++ show (getCode childNode) ++ ", " ++ show initCounters) False = undefined
numerateNode ancestorNode childNode initCounters inMeta = {-trace ("numeration result " ++ show homologs) $-} (setHomologies childNode homologs, counts, insertionEvents)
        where
            numeration = --trace ("numeration zip on " ++ show (ancestorNode) ++" and " ++ show (childNode)) 
                          V.zipWith3 numerateOne (getForAlign ancestorNode) (getForAlign childNode) initCounters 
            (homologs, counts, insertionEvents) = {-trace ("numerate results " ++ show numeration) $-} V.unzip3 numeration


numerateOne :: SeqConstraint s => s -> s -> Counter -> (Homologies, Counter, IntSet)
--numerateOne ancestorSeq descendantSeq ancestorHomologies initialCounter | trace ("numerateOne on " ++ show ancestorSeq ++" and " ++ show descendantSeq) False = undefined
numerateOne ancestorSeq descendantSeq (maxLen, initialCounter) = (descendantHomologies, (newLen, counter'), insertionEvents)
  where
    gapCharacter = gapChar descendantSeq
    newLen = max (numChars descendantSeq) maxLen

    descendantHomologies = V.generate (olength descendantSeq) g
     where
       g :: Int -> Int
       g i = fromMaybe (error "The apparently not impossible happened!") $ i `IM.lookup` mapping

    (Accum (mapping, counter', _, _, _, insertionEvents)) = ofoldl' f (Accum (mempty, initialCounter, 0, 0, 0, mempty)) descendantSeq
      where
        f (Accum (indexMapping, counter, i, ancestorOffset, childOffset, insertionEventIndicies)) _ -- Ignore the element parameter because the compiler can't make the logical type deduction :(
          -- Biological "Nothing" case
          | ancestorCharacter == gapCharacter && descendantCharacter == gapCharacter = Accum (insert i (i + childOffset    ) indexMapping, counter    , i + 1, ancestorOffset    , childOffset    , insertionEventIndicies)
          -- Biological deletion event case
          | ancestorCharacter /= gapCharacter && descendantCharacter == gapCharacter = Accum (insert i (i + childOffset + 1) indexMapping, counter + 1, i + 1, ancestorOffset    , childOffset + 1, insertionEventIndicies)
          -- Biological insertion event case
          | ancestorCharacter == gapCharacter && descendantCharacter /= gapCharacter = Accum (insert i (i + childOffset    ) indexMapping, counter + 1, i + 1, ancestorOffset + 1, childOffset + 1, (i + childOffset + 1) `IS.insert` insertionEventIndicies)
          -- Biological substitution or non-substitution case
          | otherwise {- Both not gap -}                                             = Accum (insert i (i + childOffset)     indexMapping, counter    , i + 1, ancestorOffset    , childOffset    , insertionEventIndicies)
          where
--          j = i + childOffset
            descendantCharacter    = fromJust $ safeGrab descendantSeq i
            ancestorCharacter = fromJust $ safeGrab ancestorSeq   i 

-- TODO: make sure a sequence always ends up in FinalGapped to avoid this decision tree
-- | Simple function to get a sequence for alignment purposes
getForAlign :: NodeConstraint n s => n -> Vector s
getForAlign n 
    | not . null $ getFinalGapped n = getFinalGapped n
    | not . null $ getPreliminary n = getPreliminary n 
    | not . null $ getEncoded     n = getEncoded n 
    | otherwise = mempty {-error "No sequence at node for IA to numerate"-}


-- | Function to do a numeration on an entire node
-- given the parent node, child node, current counter vector, and vector of metadata
-- returns a tuple with the node with homologies incorporated, and a returned vector of counters
comparativeNumeration :: (NodeConstraint n s, Metadata m s) => n -> n -> Vector (IntMap Int) -> Vector m -> (n, Vector (IntMap Int), Vector IntSet)
comparativeNumeration parentNode childNode totalGapCounts _inMeta = (setHomologies childNode homologs, totalGapCounts', insertionEvents)
  where
    totalGapCounts' = V.zipWith (IM.insert (0 {- We need a unique index for each node here or for each sewuence -})) childGapCounts totalGapCounts
    numeration      = V.zipWith characterNumeration (getForAlign parentNode) (getForAlign childNode)
    (homologs, childGapCounts, insertionEvents) = V.unzip3 numeration
                                                                                                                                            
characterNumeration :: SeqConstraint s => s -> s -> (Homologies, Int, IntSet)
characterNumeration = undefined
{-
characterNumeration ancestorSeq descendantSeq = (descendantHomologies, totalGaps, insertionEvents)                                          
  where                                                                                                                                     
    gap = gapChar descendantSeq                                                                                                             
    descendantHomologies = V.fromList . reverse $ indices                                                                                   
    YAA (_, totalGaps, indices, insertionEvents) = ofoldl' f (YAA (0, 0, [], mempty)) descendantSeq                                         
      where                                                                                                                                 
        f (YAA (i, counter, hList, insertionIndices)) _                                                                                     
          -- Biological "Nothing" case                                                                                                      
          | ancestorCharacter == gap && descendantCharacter == gap = YAA (i + 1, counter + 1,     hList,               insertionIndices)    
          -- Biological insertion event case                                                                                                
          | ancestorCharacter == gap && descendantCharacter /= gap = YAA (i + 1, counter    , i : hList, i `IS.insert` insertionIndices)    
          -- Biological deletion event case                                                                                                 
          | ancestorCharacter /= gap && descendantCharacter == gap = YAA (i + 1, counter + 1,     hList,               insertionIndices)    
          -- Biological substitution / non-substitution case                                                                                
          | otherwise {- Both not gap -}                           = YAA (i + 1, counter    , i : hList,               insertionIndices)    
          where                                                                                                                             
            descendantCharacter    = fromJust $ safeGrab descendantSeq i                                                                    
            ancestorCharacter      = fromJust $ safeGrab ancestorSeq   i 
-}

type AncestorDeletionEvents    = IntSet
type AncestorInsertionEvents   = IntSet
type DescendantInsertionEvents = IntSet

newtype MemoizedEvents = Memo (DeletionEvents, AncestorInsertionEvents, InsertionEvents)

instance Monoid MemoizedEvents where
  mempty  = Memo (mempty, mempty, mempty)
  (Memo (a,b,c)) `mappend` (Memo (x,y,z)) = Memo (a<>x, b<>y, c<>z)

newtype DeletionEvents = DE (IntMap Int)
instance Monoid DeletionEvents where
  mempty = DE mempty
  (DE ancestorSet) `mappend` (DE descendantSet) = DE $ incrementedAncestorSet <> descendantSet
    where
      incrementedAncestorSet = foldlWithKey' f ancestorSet descendantSet 
      f acc i desc = foldlWithKey' g mempty acc
        where
          g im k v
            | v >= desc = IM.insert (k + 1) v im
            | otherwise = IM.insert  k      v im

newtype InsertionEvents = IE (IntMap Int)
instance Monoid InsertionEvents where
  mempty = IE mempty
  (IE ancestorSet) `mappend` (IE descendantSet) = IE $ incrementedAncestorSet <> descendantSet
    where
      incrementedAncestorSet = foldlWithKey' f ancestorSet descendantSet 
      f acc i desc = foldlWithKey' g mempty acc
        where
         g im k v
            | v >= desc = IM.insert (k + 1) v im
            | otherwise = IM.insert  k      v im

numeration :: (Eq n, TreeConstraint t n e s) => t -> t
numeration tree = tree
  where
    rootNode        = root tree
    enumeratedNodes = enumerateNodes tree
    nodeCount       = length enumeratedNodes
    rootIndex       = 0 -- locateRoot enumeratedNodes rootNode
    childMapping    = gatherChildren enumeratedNodes tree
    parentMapping   = gatherParents  childMapping    rootIndex
    homologyMemoize :: Matrix MemoizedEvents
    homologyMemoize = matrix nodeCount nodeCount opt
      where
        opt (i,j)
          -- Base case with root node
          | i == rootIndex && j == rootIndex  = Memo (mempty, mempty, allDescendantInsertion)
          -- Is a child of the root node
          | i == rootIndex                    = Memo
                                                ( ancestoralDeletions    <> deletes
                                                , IS.fromList . IM.keys $ (\(IE x) -> x) rootInsertions
                                                , allDescendantInsertion <> inserts
                                                )
          -- In the lower triange, never referenced
          | i >  j                            = Memo (mempty, mempty, mempty)
          -- Not a direct descendant
          | j `onotElem` (childMapping V.! i) = Memo (mempty, mempty, mempty)
          -- Accumulate insertions & deletions.
          | i == j                            = Memo
                                                ( ancestoralDeletions
                                                , ancestoralInsertions
                                                , mempty
                                                )
          | otherwise                         = Memo
                                                ( ancestoralDeletions    <> deletes
                                                , ancestoralInsertions   <> (\(IE x) -> IS.fromList $ IM.keys x) inserts
                                                , allDescendantInsertion <> inserts
                                                )
          where
            (deletes, inserts) = comparativeIndelEvents parentCharacter childCharacter 
            parentCharacter = fromMaybe (error "No perent Sequence!") . headMay . getForAlign $ enumeratedNodes V.! i
            childCharacter  = fromMaybe (error "No child sequence!" ) . headMay . getForAlign $ enumeratedNodes V.! j
            Memo (                  _,                    _, rootInsertions) = homologyMemoize ! (0,0)
            Memo (ancestoralDeletions, ancestoralInsertions,              _) = homologyMemoize ! (parentMapping V.! i, i) 
            allDescendantInsertion = f `ofoldMap` (childMapping V.! i)
            f x = directChildInsertions
              where
                Memo (_,_,directChildInsertions) = homologyMemoize ! (j, x)

enumerateNodes :: TreeConstraint t n e s  => t -> Vector n
enumerateNodes tree = V.generate (numNodes tree) (getNthNode tree)

locateRoot :: (Eq n, TreeConstraint t n e s) => Vector n -> n -> Int
locateRoot ns n = fromMaybe 0 $ V.ifoldl' f Nothing ns
  where
    f acc i e 
      | e == n    = acc <|> Just i
      | otherwise = Nothing

gatherChildren :: (Eq n, TreeConstraint t n e s) => Vector n -> t -> Vector IntSet
gatherChildren enumNodes tree = V.generate (length enumNodes) f
  where
    f i = IS.fromList $ location <$> children'
      where
        children'  = children node tree
        node       = enumNodes V.! i
        location n = fromMaybe (-1) $ V.ifoldl' g Nothing enumNodes
          where
            g acc i e =
              if   n == e
              then acc <|> Just i
              else acc


gatherParents :: Vector IntSet -> Int -> Vector Int
gatherParents = undefined

gatherSubtree :: ({- Eq n, -} TreeConstraint t n e s) => Vector IntSet -> Int -> BitMatrix
gatherSubtree = undefined

comparativeIndelEvents :: SeqConstraint s => s -> s -> (DeletionEvents, InsertionEvents)                                                               
comparativeIndelEvents ancestorSeq descendantSeq = (deletionEvents, insertionEvents)                                          
  where
    deletionEvents  = mempty
    insertionEvents = mempty
{-
    gap = gapChar descendantSeq
    descendantHomologies = V.fromList . reverse $ indices                                                                                   
    YAA (_, totalGaps, indices, insertionEvents) = ofoldl' f (YAA (0, 0, [], mempty)) descendantSeq                                         
      where                                                                                                                                 
        f (YAA (i, counter, hList, insertionIndices)) _                                                                                     
          -- Biological "Nothing" case                                                                                                      
          | ancestorCharacter == gap && descendantCharacter == gap = YAA (i + 1, counter + 1,     hList,               insertionIndices)    
          -- Biological insertion event case                                                                                                
          | ancestorCharacter == gap && descendantCharacter /= gap = YAA (i + 1, counter    , i : hList, i `IS.insert` insertionIndices)    
          -- Biological deletion event case                                                                                                 
          | ancestorCharacter /= gap && descendantCharacter == gap = YAA (i + 1, counter + 1,     hList,               insertionIndices)    
          -- Biological substitution / non-substitution case                                                                                
          | otherwise {- Both not gap -}                           = YAA (i + 1, counter    , i : hList,               insertionIndices)    
          where                                                                                                                             
            descendantCharacter    = fromJust $ safeGrab descendantSeq i                                                                    
            ancestorCharacter      = fromJust $ safeGrab ancestorSeq   i 
-}