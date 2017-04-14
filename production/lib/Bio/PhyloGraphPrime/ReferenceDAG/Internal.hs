-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.PhyloGraphPrime.ReferenceDAG.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, TypeFamilies #-}

module Bio.PhyloGraphPrime.ReferenceDAG.Internal where

import           Bio.PhyloGraphPrime.Component
import           Control.Arrow              ((&&&),(***))
import           Data.Bifunctor
import           Data.Foldable
import           Data.Hashable              (Hashable)
import qualified Data.HashMap.Strict as HM
import           Data.IntMap                (IntMap)
import qualified Data.IntMap         as IM
import           Data.IntSet                (IntSet)
import qualified Data.IntSet         as IS
import           Data.Key
import           Data.List                  (intercalate)
import           Data.List.NonEmpty         (NonEmpty)
import qualified Data.List.NonEmpty  as NE
import           Data.Monoid                ((<>))
import           Data.MonoTraversable
import           Data.Vector                (Vector)
import qualified Data.Vector         as V
import           Data.Vector.Instances      ()
import           Prelude             hiding (lookup)

import           Debug.Trace


-- |
-- A constant time access representation of a directed acyclic graph.
data  ReferenceDAG e n
    = RefDAG
    { references :: Vector (IndexData e n)
    , rootRefs   :: NonEmpty Int
    , graphData  :: GraphData
    }


-- |
-- A labeled record for each "node" in the graph containing the node decoration,
-- a set of parent references, and a set of child references with edge decorations.
data  IndexData e n
    = IndexData
    { nodeDecoration :: n
    , parentRefs     :: IntSet
    , childRefs      :: IntMap e
    } deriving (Show)


-- | Annotations which are global to the graph
data  GraphData
    = GraphData
    { cost :: Double
    } deriving (Show)


-- |
-- A reference to a node within the 'ReferenceDAG'.
newtype NodeRef = NR Int deriving (Eq, Enum)
                   

-- | (✔)
instance Bifunctor ReferenceDAG where

    bimap f g dag =
        RefDAG
        { references = h <$> references dag
        , rootRefs   = rootRefs  dag
        , graphData  = graphData dag
        }
      where
        h (IndexData node parentRefs' childRefs') = IndexData (g node) parentRefs' $ f <$> childRefs'


-- | (✔) 
instance Foldable (ReferenceDAG e) where

    foldMap f = foldMap (f . nodeDecoration) . references


type instance Key (ReferenceDAG e) = Int


instance FoldableWithKey (ReferenceDAG e) where

    {-# INLINE foldrWithKey #-}
    foldrWithKey f e = V.ifoldr' (\i n a -> f i (nodeDecoration n) a) e . references

    {-# INLINE foldlWithKey #-}
    foldlWithKey f e = V.ifoldl' (\a i -> f a i . nodeDecoration) e . references


-- | (✔)
instance Functor (ReferenceDAG e) where

    fmap f dag =
        RefDAG
        { references = g <$> references dag
        , rootRefs   = rootRefs  dag
        , graphData  = graphData dag
        }
      where
        g (IndexData node parentRefs' childRefs') = IndexData (f node) parentRefs' childRefs'


-- | (✔)
instance PhylogeneticComponent (ReferenceDAG e n) NodeRef e n where

    parents   i dag = fmap toEnum . otoList . parentRefs $ references dag ! fromEnum i
 
    children  i dag = fmap toEnum . IM.keys . childRefs  $ references dag ! fromEnum i

    roots           = fmap toEnum . rootRefs

    leaves          = foldMapWithKey f . references
      where
        f i x
          | null $ childRefs x = [toEnum i]
          | otherwise          = mempty

    nodeCount       = length . references

    nodeDatum i dag = nodeDecoration $ references dag ! fromEnum i

    edgeDatum (i,j) dag =  fromEnum j `lookup` childRefs (references dag ! fromEnum i)

    -- TODO: Broken
    isComponentNode i dag = olength ps > 2
      where
        ps = parentRefs $ references dag ! fromEnum i

    -- TODO: Broken
    isNetworkNode i dag = olength ps > 2
      where
        ps = parentRefs $ references dag ! fromEnum i

    isTreeNode i dag = olength ps == 1 && length cs == 2
      where
        iPoint = references dag ! fromEnum i 
        ps = parentRefs iPoint
        cs = childRefs  iPoint

    isLeafNode i dag =  null . childRefs  $ references dag ! fromEnum i

    isRootNode i dag = onull . parentRefs $ references dag ! fromEnum i

    -- TODO: Broken
    networkResolutions = pure


-- | (✔)
instance PhylogeneticNetwork (ReferenceDAG e n) NodeRef e n where

    root = toEnum . NE.head . rootRefs
  
    -- TODO: Broken
    treeResolutions = pure


-- | (✔)
instance PhylogeneticTree (ReferenceDAG e n) NodeRef e n where

    parent i dag = fmap toEnum . headMay . otoList . parentRefs $ references dag ! fromEnum i


-- | (✔)
instance {- (Show e, Show n) => -} Show (ReferenceDAG e n) where

    show = referenceRendering 


-- |
-- Probably, hopefully /O(n)/. 
--
-- Build the graph functionally from a generating function.
--
-- The generating function produces three results:
--
-- 1. A list of parent edge decorations and corresponding ancestral values
--
-- 2. The node decoration for the input value
--
-- 3. A list of child edge decorations and corresponding descendent values
unfoldDAG :: (Eq a, Hashable a, Monoid e)
          => (a -> ([(e,a)], n, [(e,a)]))
          -> a
          -> ReferenceDAG e n
unfoldDAG f origin =
    RefDAG
    { references = referenceVector
    , rootRefs   = NE.fromList roots2 -- otoList rootIndices
    , graphData  = GraphData 0
    }
  where
    referenceVector = V.fromList . fmap h $ toList expandedMap
      where
        h (iSet, nDatum, iMap) =
            IndexData
            { nodeDecoration = nDatum
            , parentRefs     = iSet
            , childRefs      = iMap
            }

    {-
    expandedMap = contractToContiguousVertexMapping $ traceShowMapping $ expandVertexMapping $ traceShowMapping resultMap
      where
        traceShowMapping v = trace (show $ fmap (\(x,_,y) -> (x, IM.keys y)) v) v
    -}
    expandedMap = resultMap

    -- TODO:
    -- _rootIndices seems to be wrong so we do this.
    -- slightly inefficient, see if we can correct the _rootIndices value.
    roots2 = foldMapWithKey h resultMap
      where
        h k (v,_,_)
          | onull v   = [k]
          | otherwise = []

    initialAccumulator = (-1, -1, (Nothing,mempty), mempty, mempty)
    (_, _, _, _rootIndices, resultMap) = g initialAccumulator origin
    g (counter, _otherIndex, previousContext@(previousIndex, previousSeenSet), currentRoots, currentMap) currentValue =
        case currentValue `lookup` previousSeenSet of
          -- If this value is in the previously seen set we don't recurse.
          -- We just return the supplied accumulator with a mutated otherIndex value.
          Just i  -> (counter, i, previousContext, currentRoots, currentMap)
          Nothing -> result
      where
        result = ( cCounter
                 , currentIndex
                 , resultContext
                 , currentRoots <> pRoots <> cRoots <> localRoots
                 , cMap <> mapWithLocalChildren <> mapWithLocalParents <> mapWithLocalValues
                 )
        
        (fullParentPairs, newDatum, fullChildPairs) = f currentValue
        (omittedParentPairs, parentPairs) = omitOriginPath fullParentPairs
        (omittedChildPairs , childPairs ) = omitOriginPath fullChildPairs

        currentIndex   = counter + 1
        currentContext = (Just currentIndex, HM.insert currentValue currentIndex previousSeenSet)

        resultContext  = (previousIndex, snd cContext)

        omitOriginPath = foldr h ([],[])
          where
            h y@(e,v) (xs,ys) =
              case v `lookup` previousSeenSet of
                Nothing -> (        xs, y:ys)
                Just i  -> ((e,v,i):xs,   ys)

        parentResursiveResult          = NE.scanr (\e a -> second (g (snd a)) e) (undefined, (currentIndex, undefined, currentContext, currentRoots, currentMap)) parentPairs
        (pCounter, _, pContext, pRoots, pMap) = snd $ NE.head parentResursiveResult
        childResursiveResult           = NE.scanr (\e a -> second (g (snd a)) e) (undefined, (pCounter, undefined, pContext, pRoots, pMap)) childPairs
        (cCounter, _, cContext, cRoots, cMap) = snd $ NE.head childResursiveResult

        mapWithLocalParents = foldMap h $ NE.init parentResursiveResult
          where
            h (_,(_,c,_,_,_)) = IM.insertWith insWith cCounter (IS.singleton c, newDatum, mempty) cMap
              where
                insWith (niSet, _, niMap) (oiSet, dec, oiMap) = (niSet <> oiSet, dec, oiMap <> niMap)

        mapWithLocalChildren = foldMap h $ NE.init childResursiveResult
          where
            h (e,(_,c,_,_,_)) = IM.insertWith insWith cCounter (mempty, newDatum, IM.singleton c e) cMap
              where
                insWith (niSet, _, niMap) (oiSet, dec, oiMap) = (niSet <> oiSet, dec, oiMap <> niMap)

        mapWithLocalValues  = IM.singleton currentIndex
                            ( otherParents  <> resultParents
                            , newDatum
                            , otherChildren <> resultChildren
                            )
          where
            otherParents   = foldMap (\(_,_,i)         -> IS.singleton i  ) omittedParentPairs
            otherChildren  = foldMap (\(e,_,i)         -> IM.singleton i e) omittedChildPairs
            resultParents  = foldMap (\(_,(_,c,_,_,_)) -> IS.singleton c  ) $ NE.init parentResursiveResult
            resultChildren = foldMap (\(e,(_,c,_,_,_)) -> IM.singleton c e) $ NE.init childResursiveResult

        localRoots
          | null fullParentPairs = IS.singleton cCounter
          | otherwise            = mempty


-- |
-- Applies a traversal logic function over a 'ReferenceDAG' in a /post-order/ manner.
--
-- The logic function takes a current node decoration,
-- a list of child node decorations with the logic function already applied,
-- and returns the new decoration for the current node.
nodePostOrder :: (n -> [n'] -> n') -> ReferenceDAG e n -> ReferenceDAG e n'
nodePostOrder f dag = RefDAG <$> const newReferences <*> rootRefs <*> graphData $ dag
  where
    dagSize       = length $ references dag
    newReferences = V.generate dagSize h
      where
        h i = IndexData <$> const (memo ! i) <*> parentRefs <*> childRefs $ references dag ! i
    memo = V.generate dagSize h
      where
        h i = f datum $ (memo !) <$> childIndices
          where
            datum        = nodeDecoration node 
            node         = references dag ! i
            childIndices = IM.keys $ childRefs node


-- |
-- Applies a traversal logic function over a 'ReferenceDAG' in a /pre-order/ manner.
--
-- The logic function takes a current node decoration,
-- a list of parent node decorations with the logic function already applied,
-- and returns the new decoration for the current node.
nodePreOrder :: (n -> [(Word, n')] -> n') -> ReferenceDAG e n -> ReferenceDAG e n'
nodePreOrder f dag = RefDAG <$> const newReferences <*> rootRefs <*> graphData $ dag
  where
    dagSize       = length $ references dag
    newReferences = V.generate dagSize h
      where
        h i = IndexData <$> const (memo ! i) <*> parentRefs <*> childRefs $ references dag ! i
    memo = V.generate dagSize h
      where
        h i = f datum $ (childPosition &&& (memo !)) <$> parentIndices
          where
            node            = references dag ! i
            datum           = nodeDecoration node 
            parentIndices   = otoList $ parentRefs node
            -- In sparsely connected graphs (like ours) this will be effectively constant.
            childPosition j = toEnum . length . takeWhile (/=i) . IM.keys . childRefs $ references dag ! j



-- |
-- Renders the 'ReferenceDAG' without showing the node or edge decorations.
-- Displays a multi-line, tabular reference map of the 'ReferenceDAG'. 
referenceRendering :: ReferenceDAG e n -> String
referenceRendering dag = unlines $ [shownRootRefs] <> toList shownDataLines
  where
    shownRootRefs   = listShow . toList $ rootRefs dag
    
    shownRefs       = f <$> references dag
      where
        f (IndexData _ pRefs cRefs) = (listShow $ otoList pRefs, listShow $ IM.keys cRefs)

    shownTrimmedParentRefs = fst <$> shownRefs
    
    shownTrimmedChildRefs  = snd <$> shownRefs

    shownPaddedParentRefs  = pad maxParentWidth <$> shownTrimmedParentRefs
    
    shownPaddedChildRefs   = pad maxChildWidth  <$> shownTrimmedChildRefs

    maxParentWidth = maximum $ length <$> shownTrimmedParentRefs

    maxChildWidth  = maximum $ length <$> shownTrimmedChildRefs

    maxIndexWidth  = length . show . pred . length $ references dag

    shownDataLines = zipWithKey f shownPaddedParentRefs shownPaddedChildRefs
      where
        f i p c = "  " <> unwords [ pad maxIndexWidth $ show i, p, c]

    listShow = (\x -> "{" <> x <> "}") . intercalate "," . fmap show

    pad n    []  = replicate n ' '
    pad 0    xs  = xs
    pad n (x:xs) = x : pad (n-1) xs


nodeFoldMap :: Monoid m => (n -> m) -> ReferenceDAG e n -> m
nodeFoldMap f = foldMap f . fmap nodeDecoration . references

-- A test for unfoldDAG containing all node types!
{--

dataDef1 :: [(Char,String)]
dataDef1 = [('R',"AB"),('A',"CD"),('B',"CE"),('C',[]),('D',[]),('E',[]),('Z',"BF"),('F',"GH"),('G',[]),('H',[])]

gen1 :: Char -> ([(Int,Char)], String, [(Int,Char)])
gen1 x = (pops, show x, kids)
  where
    pops = foldMap (\(i,xs) -> if x `elem` xs then [(-1,i)] else []) dataDef1
    kids =
      case Pre.lookup x dataDef1 of
        Nothing -> []
        Just xs -> (\y -> (-1,y)) <$> xs
--}


-- |
-- /O(n*i)/ where /i/ is the number of missing indicies.
-- Assuming all indicies in the input /x/ are positive, /i/ = 'findMax x - length x'.
--
-- Takes an IntMap that might not have a contiguous index range and makes the
-- range contiguous [0, length n - 1].
contractToContiguousVertexMapping :: IntMap (IntSet, t, IntMap a) -> IntMap (IntSet, t, IntMap a)
contractToContiguousVertexMapping inputMap = foldMapWithKey contractIndices inputMap
  where
    missingIndicies = otoList . snd . foldl' f (0, mempty) $ IM.keys inputMap
      where
        f (expectedValue, missing) actualValue
          | expectedValue == actualValue = (expectedValue + 1, missing)
          | otherwise                    = (  actualValue + 1, missing <> IS.fromList [expectedValue .. actualValue - 1])

    decrementIndex originalIndex = originalIndex - subtrahend
      where
        subtrahend = length $ takeWhile (<originalIndex) missingIndicies

    contractIndices key (iSet, datum, iMap) = IM.singleton key' value'
      where
        key'   = decrementIndex key
        value' = (IS.map decrementIndex iSet, datum, IM.mapKeysMonotonic decrementIndex iMap) 
    

-- TODO: Test this and make sure it works!
expandVertexMapping :: Monoid a => IntMap (IntSet, t, IntMap a) -> IntMap (IntSet, t, IntMap a)
expandVertexMapping unexpandedMap = snd . foldl' f (initialCounter, unexpandedMap) $ IM.keys unexpandedMap
  where
    (initialCounter, _) = IM.findMax unexpandedMap
    
    f acc key = expandEdges acc key

    expandEdges acc@(counter, mapping) key =
        case parentCount of
          0 -> if   childCount <= 2
               then acc
               else handleTooManyChildren

          1 -> case childCount of
                  0 -> acc
                  1 -> collapseEdge
                  2 -> acc
                  -- One too many childern
                  3 -> expandOutExtraChild
                  -- Far too many children
                  _ -> handleTooManyChildren

          2 -> case childCount of
                  0 -> expandOutVertexToChild
                  1 -> acc
                  -- Too many children
                  _ -> expandEdges expandOutVertexToChild counter

          -- One too many parents
          3 -> expandEdges expandOutExtraParent counter

          -- Far too many parents
          _ -> expandEdges handleTooManyParents key
          
      where
        (iSet, nDatum, iMap) = mapping ! key

        parentCount = olength iSet
        childCount  =  length iMap

        -- To collapse an edge
        collapseEdge = (counter, collapsedEdgeMapping)
          where
            updateAncestoralEdge (x,y,z) = (IS.insert parentKey $ IS.delete key x, y, z)
            updateDescendentEdge (x,y,z) = (x, y, IM.insert childKey edgeValue $ IM.delete key z)
            parentKey             = IS.findMin iSet
            (childKey, edgeValue) = IM.findMin iMap
            collapsedEdgeMapping  = IM.adjust updateAncestoralEdge  childKey 
                                  . IM.adjust updateDescendentEdge parentKey
                                  . IM.delete key
                                  $ mapping

        
        expandOutVertexToChild = (counter + 1, expandedMapping)
          where
            ancestoralVertex = (            iSet, nDatum, IM.singleton counter mempty)
            descendentVertex = (IS.singleton key, nDatum,                        iMap)

            updateParent = flip (adjust setParent)
              where
                setParent (_,y,z) = (IS.singleton counter, y, z) 

            expandedMapping  = replace counter descendentVertex
                             . replace key     ancestoralVertex
                             . foldl' updateParent mapping
                             $ IM.keys iMap


        expandOutExtraChild  = (counter + 1, expandedMapping)
          where
            ancestoralVertex = (            iSet, nDatum, singledChildMap)
            descendentVertex = (IS.singleton key, nDatum, reducedChildMap)

            singledChildMap  = IM.singleton counter mempty <> IM.singleton minChildKey edgeValue
            reducedChildMap  = IM.delete minChildKey iMap

            (minChildKey, edgeValue) = IM.findMin iMap

            updateParent = flip (adjust setParent)
              where
                setParent (_,y,z) = (IS.singleton counter, y, z) 

            expandedMapping  = replace counter descendentVertex
                             . replace key     ancestoralVertex
                             . foldl' updateParent mapping
                             $ IM.keys reducedChildMap


        handleTooManyChildren = rhsRecursiveResult
          where
            (lhsChildMap, rhsChildMap) = (IM.fromList *** IM.fromList) . splitAt (childCount `div` 2) $ toKeyedList iMap
            
            ancestoralVertex = (            iSet, nDatum, newChildMap)
            lhsNewVertex     = (IS.singleton key, nDatum, lhsChildMap)
            rhsNewVertex     = (IS.singleton key, nDatum, rhsChildMap)

            newChildMap      = IM.singleton counter mempty <> IM.singleton (counter+1) mempty

            lhsUpdateParent = flip (adjust setParent)
              where
                setParent (_,y,z) = (IS.singleton  counter  , y, z) 

            rhsUpdateParent = flip (adjust setParent)
              where
                setParent (_,y,z) = (IS.singleton (counter+1), y, z) 

            expandedMapping  = replace  counter    lhsNewVertex
                             . replace (counter+1) rhsNewVertex 
                             . replace  key        ancestoralVertex
                             . flip (foldl' rhsUpdateParent) (IM.keys rhsChildMap)
                             . foldl' lhsUpdateParent mapping
                             $ IM.keys lhsChildMap

            lhsRecursiveResult = expandEdges (counter+2, expandedMapping) counter
            rhsRecursiveResult = expandEdges lhsRecursiveResult (counter+1)
            
        
        expandOutExtraParent = (counter + 1, expandedMapping)
          where
            ancestoralVertex = (reducedParentMap, nDatum, singledChildMap)
            descendentVertex = (singledParentMap, nDatum,            iMap)

            
            singledChildMap  = IM.singleton counter mempty
            singledParentMap = IS.fromList [key, maxParentKey]
            reducedParentMap = IS.delete    maxParentKey iSet

            maxParentKey = IS.findMax iSet

            updateChildRef (x,y,z) = (x, y, replace counter (z ! key) $ IM.delete key z)

            updateParent = flip (adjust setParent)
              where
                setParent (_,y,z) = (IS.singleton counter, y, z) 

            expandedMapping  = replace counter descendentVertex
                             . replace key     ancestoralVertex
                             . adjust updateChildRef maxParentKey
                             . foldl' updateParent mapping
                             $ IM.keys iMap


        handleTooManyParents = rhsRecursiveResult
          where
            (lhsParentSet, rhsParentSet) = (IS.fromList *** IS.fromList) . splitAt (childCount `div` 2) $ otoList iSet
            
            descendantVertex = (newParentSet, nDatum, iMap)
            lhsNewVertex     = (lhsParentSet, nDatum, IM.singleton key mempty)
            rhsNewVertex     = (rhsParentSet, nDatum, IM.singleton key mempty)

            newParentSet = IS.fromList [counter, counter+1]

            lhsUpdateChildren = flip (adjust setChild)
              where
                setChild (x,y,z) = (x, y, replace  counter    (z ! key) $ IM.delete key z)

            rhsUpdateChildren = flip (adjust setChild)
              where
                setChild (x,y,z) = (x, y, replace (counter+1) (z ! key) $ IM.delete key z)

            expandedMapping = replace  counter    lhsNewVertex
                            . replace (counter+1) rhsNewVertex 
                            . replace  key        descendantVertex
                            . flip (ofoldl' rhsUpdateChildren) rhsParentSet
                            . ofoldl' lhsUpdateChildren mapping
                            $ lhsParentSet

            lhsRecursiveResult = expandEdges (counter+2, expandedMapping) counter
            rhsRecursiveResult = expandEdges lhsRecursiveResult (counter+1)

        

