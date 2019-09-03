{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE LambdaCase          #-}

module Data.Graph.Intermediate where

import Data.Graph.Type
import Data.Tree (Tree(..), unfoldForestM, drawForest, Forest)
import Data.Map hiding ((!), fromList)
import qualified Data.Set as S
import Data.Set (Set)
import Data.Graph.NodeContext
import Control.Lens
import Data.Vector hiding (fromList, modify)
import Data.Graph.Indices
import Data.Graph.NodeContext
import Data.Pair.Strict
import Data.Coerce
import qualified Data.Foldable as F
import Control.Monad.State.Strict
import Control.Comonad

type Size = Int

data RenderNodeLabel a netRef =
  RenderNodeLabel
  { _name      :: a
  , _size      :: Int
  , _netRef    :: Maybe netRef
  , _indexInfo :: Focus
  }

type RoseForest a netRef = [Tree (a, Focus, Maybe netRef)]
  

leafR :: a -> Tree (a, Maybe netRef)
leafR name = Node (name, Nothing) []


branchR :: a -> Tree (a, Maybe netRef) -> Tree (a, Maybe netRef) -> Tree (a, Maybe netRef)
branchR name lTree rTree = Node (name, Nothing) [lTree, rTree]


networkR :: a -> netRef -> Tree (a, Maybe netRef) -> Tree (a, Maybe netRef)
networkR name netRef subTree = Node (name, Just netRef) [subTree]


data ReferenceNode l n ref = LeafRN l ref | NetworkRN !Size n ref | BranchRN !Size ref ref

data ReferenceMap l n ref = ReferenceMap
  { _rootRefs     :: [ref]
  , _networkRefs  :: [ref]
  , _refMap       :: Map ref (ReferenceNode l n ref)
  }


data BinaryTree l i n =
  LeafBT l | NetworkBT i n !Size  | BranchBT !Size i (BinaryTree l i n) (BinaryTree l i n)


toRoseForest
  :: forall f c e n t a netRef . (Ord netRef)
  => (t -> a)
  -> (f n -> a)
  -> (NetworkInd -> netRef)
  -> Graph f e c n t
  -> RoseForest a netRef
toRoseForest leafConv internalConv netConv graph =
  (unfoldForestM build rootFocusGraphs) `evalState` mempty
  where
    rootFocusGraphs :: [RootFocusGraph f e c n t]
    rootFocusGraphs = makeRootFocusGraphs graph

    build
      :: RootFocusGraph f e c n t
      -> State (Set netRef) ((a, Focus, Maybe netRef), [RootFocusGraph f e c n t])
    build (focus :!: graph) =
      case focus of
        LeafTag :!: untaggedInd ->
          let
            leafNodeInfo    = view (_leafReferences . singular (ix untaggedInd)) graph
            nodeName        = leafConv . (view _nodeData) $ leafNodeInfo
          in
            pure ((nodeName, focus, Nothing), [])
        NetworkTag :!: untaggedInd ->
          let
            nodeInfo = view (_networkReferences . singular (ix untaggedInd)) graph
            nodeName = internalConv $ view _nodeData nodeInfo
            netRef   = netConv (coerce untaggedInd)
            childInd = view _childInds nodeInfo
            newFocus = toUntagged childInd
          in
            do
              seenNetRefs <- get
              case netRef `S.member` seenNetRefs of
                True  -> pure ((nodeName, focus, Just netRef), [])
                False ->
                  do
                    modify (S.insert netRef)
                    pure ((nodeName, focus, Just netRef), [newFocus :!: graph])

        TreeTag    :!: untaggedInd ->
          let
            nodeInfo = view (_treeReferences . singular (ix untaggedInd)) graph
            nodeName = internalConv $ view _nodeData nodeInfo
            leftChildInd :!: rightChildInd = view _childInds nodeInfo
            leftFocus = toUntagged leftChildInd
            rightFocus = toUntagged rightChildInd
          in
            pure ((nodeName, focus, Nothing), [leftFocus :!: graph, rightFocus :!: graph])
        RootTag    :!: untaggedInd ->
          let
            nodeInfo = view (_rootReferences . singular (ix untaggedInd)) graph
            nodeName = internalConv $ view _nodeData nodeInfo
            childInds = view _childInds nodeInfo
          in
            case childInds of
              Left childInd ->
                  let
                    newFocus = toUntagged childInd
                  in
                    pure ((nodeName, focus, Nothing), [newFocus :!: graph])
              Right (leftChildInd :!: rightChildInd) ->
                  let
                    leftFocus  = toUntagged leftChildInd
                    rightFocus = toUntagged rightChildInd
                  in
                    pure ((nodeName, focus, Nothing), [leftFocus :!: graph, rightFocus :!: graph])
          

makeSizeLabelledTree
  :: Tree (a, Focus, Maybe netRef)
  -> Tree (RenderNodeLabel a netRef)
makeSizeLabelledTree = extend f
  where
    f :: Tree (a, Focus, Maybe netRef) -> RenderNodeLabel a netRef
    f tree =
      let
        (name, focus, netRef) = rootLabel tree
      in
        RenderNodeLabel
          { _name = name
          , _indexInfo = focus
          , _netRef = netRef
          , _size = F.length tree
          }

makeSizeLabelledForest
  :: Forest (a, Focus, Maybe netRef)
  -> Forest (RenderNodeLabel a netRef)
makeSizeLabelledForest = fmap makeSizeLabelledTree


reorderTree :: Tree (RenderNodeLabel a netRef) -> Tree (RenderNodeLabel a netRef)
reorderTree t@(Node _ [])   = t
reorderTree t@(Node _ [_])  = t
reorderTree t@(Node root (l:r:ls))
  | (_size . rootLabel $ l) < (_size . rootLabel $ r)
    = Node root (r:l:ls)
  | otherwise
    = t

reorderForest :: Forest (RenderNodeLabel a netRef) -> Forest (RenderNodeLabel a netRef)
reorderForest = fmap reorderTree

renderRoseForest
  :: (RenderNodeLabel a netRef -> String)
  -> Forest (RenderNodeLabel a netRef)
  -> String
renderRoseForest renderFn =
  drawForest . fmap (fmap renderFn)

   
renderGraphAsRoseForest
  :: (Ord netRef)
  => (t   -> a)
  -> (f n -> a)
  -> (NetworkInd -> netRef)
  -> (RenderNodeLabel a netRef -> String)
  -> Graph f c e n t
  -> String
renderGraphAsRoseForest leafFn intFn netFn renderFn =
    renderRoseForest renderFn
  . reorderForest
  . makeSizeLabelledForest
  . (toRoseForest leafFn intFn netFn)
