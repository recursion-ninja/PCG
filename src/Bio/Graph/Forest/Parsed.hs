-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.PhyloGraph.Forest.Parsed
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Typeclass for a parsed forest so that it can convert into an internal forest.
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Bio.Graph.Forest.Parsed where

import           Bio.Graph.Forest
import           Bio.Graph.ReferenceDAG
import           Control.Arrow                    (first, (&&&))
import           Data.Coerce                      (coerce)
import           Data.EdgeLength
import           Data.Foldable
import           Data.Hashable
import           Data.IntMap                      (IntMap)
import qualified Data.IntMap                      as IM
import           Data.Key
import           Data.List.NonEmpty               (NonEmpty, nonEmpty)
import qualified Data.List.NonEmpty               as NE
import           Data.Map                         (Map, findMin)
import qualified Data.Map                         as Map
import           Data.Maybe
import           Data.Monoid
import           Data.NodeLabel
import qualified Data.Set                         as Set
import           Data.ShortText.Custom            (intToShortText)
import           Data.String                      (IsString (fromString))
import           File.Format.Dot
import           File.Format.Fasta
import           File.Format.Fastc                hiding (Identifier)
import           File.Format.Newick
import           File.Format.Nexus                hiding (TaxonSequenceMap)
import           File.Format.TNT
import           File.Format.TransitionCostMatrix
import           File.Format.VertexEdgeRoot       hiding (EdgeLength)
import qualified File.Format.VertexEdgeRoot       as VER
import           Prelude                          hiding (lookup)


-- |
-- The type of possibly-present decorations on a tree from a parsed file.
type ParserTree   = ReferenceDAG () EdgeLength (Maybe NodeLabel)


-- |
-- The parser coalesced type representing a possibly present forest.
type ParserForest = Maybe (PhylogeneticForest ParserTree)


-- |
-- The parser coalesced type representing a possibly present forest.
type ParserForestSet = Maybe (NonEmpty (PhylogeneticForest ParserTree))


-- |
-- An internal type for representing a node with a unique numeric identifier.
data NewickEnum   = NE !Int (Maybe NodeLabel) (Maybe Double) [NewickEnum]


-- |
-- Represents a parser result type which can have a possibly empty forest
-- extracted from it.
class ParsedForest a where

    unifyGraph :: a -> ParserForestSet


-- | (✔)
instance Hashable GraphID where

   hashWithSalt salt = hashWithSalt salt . show -- Lazy hash, should be fine


-- | (✔)
instance ParsedForest (DotGraph GraphID) where

    unifyGraph dot = Just . pure . PhylogeneticForest . pure $ unfoldDAG f seed
      where
        seed :: GraphID
        (seed,_) =  findMin cMapping
        cMapping =  dotChildMap  dot
        pMapping =  dotParentMap dot

        f :: GraphID -> ([(EdgeLength, GraphID)], Maybe NodeLabel, [(EdgeLength, GraphID)])
        f x = (parents, marker, kids)
           where
            kids, parents :: [(EdgeLength, GraphID)]
            kids    = fmap (const mempty &&& id) . toList $ cMapping ! x
            parents = fmap (const mempty &&& id) . toList $ pMapping ! x

            marker
              | null kids = Just . fromString . toIdentifier $ x
              | otherwise = Nothing


-- | (✔)
instance ParsedForest FastaParseResult where

    unifyGraph = const Nothing


-- | (✔)
instance ParsedForest FastcParseResult where

    unifyGraph = const Nothing


-- | (✔)
instance ParsedForest TaxonSequenceMap where

    unifyGraph = const Nothing


-- | (✔)
instance ParsedForest TCM where

    unifyGraph = const Nothing


-- | (✔)
instance ParsedForest Nexus where

    unifyGraph (Nexus _ forest) = unifyGraph =<< nonEmpty forest


-- | (✔)
instance ParsedForest (NonEmpty NewickForest) where

    unifyGraph = Just . fmap (PhylogeneticForest . fmap (coerceTree . relationMap . enumerate)) {- . (\x -> trace (unlines $ renderNewickForest <$> toList x) x) -}
      where

        -- Apply generating function by indexing adjacency matrix.
        coerceTree mapping = unfoldDAG (mapping !) 0

        -- We assign a unique index to each node by converting the node to a 'NewickEnum' type.
        enumerate :: NewickNode -> NewickEnum
        enumerate = (\(_,_,x) -> x) . f mempty 0
          where
            f :: Map NodeLabel NewickEnum -> Int -> NewickNode -> (Map NodeLabel NewickEnum, Int, NewickEnum)
            f seen n node =
              let
                nodelabel = coerce . newickLabelShort $ node
              in
                case nodelabel >>= (`lookup` seen) of
                  Just x  -> (seen, n, x)
                  Nothing ->
                    case descendants node of
                      [] -> let enumed = NE n nodelabel (branchLength node) []
                                seen'  =
                                  case newickLabel node of
                                    Nothing -> seen
                                    Just x  -> seen <> Map.singleton (nodeLabelString  x) enumed
                            in  (seen', n + 1, enumed)
                      xs -> let recursiveResult = NE.scanr (\e (x,y,_) -> f x y e) (seen, n+1, undefined) xs
                                (seen', n', _)  = NE.head recursiveResult
                                childEnumed     = (\(_,_,x) -> x) <$> NE.init recursiveResult
                                enumed          = NE n nodelabel (branchLength node) childEnumed
                                seen''          =
                                  case newickLabel node of
                                    Nothing -> seen'
                                    Just x  -> seen' <> Map.singleton (nodeLabelString x) enumed
                            in  (seen'', n', enumed)

        -- We use the unique indices from the 'enumerate' step to build a local connectivity map.
        relationMap :: NewickEnum -> IntMap ([(EdgeLength, Int)], Maybe NodeLabel, [(EdgeLength, Int)])
        relationMap root = subCall Nothing root mempty
          where
            subCall :: Maybe Int
                    -> NewickEnum
                    -> IntMap ([(EdgeLength, Int)], Maybe NodeLabel, [(EdgeLength, Int)])
                    -> IntMap ([(EdgeLength, Int)], Maybe NodeLabel, [(EdgeLength, Int)])
            subCall parentMay (NE ref labelMay costMay children) prevMap =
                case ref `lookup` prevMap of
                  Just (xs, datum, ys) -> IM.insert ref ((fromDoubleMay costMay, fromJust parentMay):xs, datum, ys) prevMap
                  Nothing              ->
                    let parentRefs =
                          case parentMay of
                            Nothing -> []
                            Just x  -> [(fromDoubleMay costMay,x)]
                        currMap    = IM.insert ref (parentRefs, labelMay, f <$> children) prevMap
                    in  foldr (subCall (Just ref)) currMap children
              where
                f (NE x _ y _) = (fromDoubleMay y,x)


-- | (✔)
instance ParsedForest TntResult where
  unifyGraph input = fmap pure $
        case input of
          Left                forest  ->
            toPhylogeneticForest getTNTName <$> Just     forest
          Right (WithTaxa _ _ forest) ->
            toPhylogeneticForest fst        <$> (nonEmpty
                                              . fmap (fmap (first nodeLabelString))
                                              $ forest)
      where

        -- | Propper fmapping over 'Maybe's and 'NonEmpty's
        toPhylogeneticForest f = PhylogeneticForest . fmap (coerceTree . enumerate f)

        -- | Apply the generating function referencing the relational mapping.
        coerceTree mapping = unfoldDAG f 0
          where
            f i = (g $ toList parentMay, datum, g childRefs)
              where
                (parentMay, datum, childRefs) = mapping ! i
                g = fmap (const mempty &&& id)

        -- | We assign a unique index to each node and create an adjcency matrix.
        enumerate :: (n -> NodeLabel) -> LeafyTree n -> IntMap (Maybe Int, Maybe NodeLabel, [Int])
        enumerate toLabel = (\(_,_,x) -> x) . f Nothing 0
          where
            f parentRef n node =
                case node of
                  Leaf   x  -> (n, n + 1, IM.singleton n (parentRef, Just $ toLabel x, []))
                  Branch xs ->
                    let recursiveResult = NE.scanr (\e (_,x,_) -> f (Just n) x e) (undefined, n + 1, undefined) xs
                        (_, counter, _) = NE.head recursiveResult
                        childrenRefs    = (\(x,_,_) -> x) <$> NE.init recursiveResult
                        subTreeMapping  = foldMap (\(_,_,x) -> x) $ NE.init recursiveResult
                        selfMapping     = IM.singleton n (parentRef, Nothing, childrenRefs)
                    in (n, counter, selfMapping <> subTreeMapping)

        -- | Conversion function for 'NodeType' to 'NodeLabel'
        getTNTName :: NodeType -> NodeLabel
        getTNTName node =
            case node of
              Index  i -> nodeLabel . intToShortText $ i
              Name   n -> nodeLabel . fromString $ n
              Prefix s -> nodeLabel . fromString $ s


{- -}
-- | (✔)
instance ParsedForest VER.VertexEdgeRoot where

    unifyGraph (VER vs es rs) =
        Just
      . pure
      . PhylogeneticForest
      . fmap convertToDAG
      . NE.fromList
      $ toList disconnectedRoots
      where

        childMapping  = foldMap (collectEdges edgeTarget) vs

        parentMapping = foldMap (collectEdges edgeOrigin) vs

        collectEdges f v = Map.singleton v $ foldMap g es
          where
            g e
              | edgeTarget e == v = Set.singleton (fromDoubleMay $ edgeLength e, f e)
              | otherwise         = mempty

        -- |
        -- We collect only disconnected roots so that we don't generate duplicate
        -- trees from connected roots.
        disconnectedRoots = foldl' f rs rs
          where
            f remainingRoots r
              | r `notElem` remainingRoots = remainingRoots
              | otherwise                  = remainingRoots `Set.difference` connectedRoots
              where
                connectedRoots = g mempty r
                g seen node
                  | node `elem` remainingRoots = Set.singleton node
                  | node `elem` seen           = mempty
                  | otherwise                  = foldMap (g seen') children
                  where
                    seen' = seen
                    children = Set.mapMonotonic snd (childMapping ! node) `Set.difference` seen

        convertToDAG = unfoldDAG f
          where
            f label = (pValues, Just . nodeLabel . fromString $ label, cValues)
              where
                pValues =
                    case label `lookup` parentMapping of
                       Nothing -> []
                       Just xs -> toList xs
                cValues =
                    case label `lookup` childMapping of
                       Nothing -> []
                       Just xs -> toList xs

{- -}

{-
-- | Convert the referential forests defined by sets of vertices, edges, and
--   roots into a forest of topological tree structure.
convertVerToNewick :: VertexEdgeRoot -> Forest NewickNode
convertVerToNewick (VER _ e r) = buildNewickTree Nothing <$> toList r
  where
    buildNewickTree :: Maybe Double -> VertexLabel -> NewickNode
    buildNewickTree c n = fromJust $ newickNode kids (Just n) c
      where
        kids = fmap (uncurry buildNewickTree) . catMaybes $ kidMay n <$> toList e
        kidMay vertex edge = do
          other <- VER.connectedVertex vertex edge
          pure (VER.edgeLength edge, other)

-- | Convert the topological 'LeafyTree' structure into a forest of topological
--   tree structures with nodes that hold additional information.
convertTntToNewick :: (n -> String) -> LeafyTree n -> NewickNode
convertTntToNewick f (Leaf   x ) = fromJust $ newickNode [] (Just $ f x) Nothing -- Scary use of fromJust?
convertTntToNewick f (Branch xs) = fromJust $ newickNode (convertTntToNewick f <$> xs) Nothing Nothing

-- | Conversion function for NodeType to string
getTNTName :: NodeType -> String
getTNTName node = case node of
    (Index i) -> show i
    (Name n) -> n
    (Prefix s) -> s
-}
