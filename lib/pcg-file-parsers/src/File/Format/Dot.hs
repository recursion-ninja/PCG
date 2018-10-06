-----------------------------------------------------------------------------
-- |
-- Module      :  File.Format.Dot
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE DerivingStrategies  #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}

module File.Format.Dot
  ( DotGraph
  , GraphID(..)
  -- ** Parse a DOT file
  , dotParse
  -- ** Get useful representations from the DOT file
  , dotChildMap
  , dotParentMap
  , dotNodeSet
  , dotEdgeSet
  , toIdentifier
  ) where


import           Control.Arrow                     ((&&&))
import           Control.Monad.State
import           Data.Foldable
import           Data.GraphViz.Attributes.Complete (Attribute (Label), Label (..))
import           Data.GraphViz.Parsing
import           Data.GraphViz.Types
import           Data.GraphViz.Types.Canonical
import           Data.Key
import           Data.Map                          (Map, fromSet, insertWith)
import           Data.Monoid
import           Data.Set                          (Set)
import qualified Data.Set                          as S
import           Data.Text                         (Text)
import qualified Data.Text.Lazy                    as L
import           Prelude                           hiding (lookup)

-- |
-- Parses the 'Text' stream from a DOT file.
dotParse :: Text -> Either String (DotGraph GraphID)
dotParse = (relabelDotGraph <$>) . fst . runParser parse . L.fromStrict

-- |
-- Takes a DotGraph and relabels the NodeID if the node has a label
relabelDotGraph :: DotGraph GraphID -> DotGraph GraphID
relabelDotGraph g =
  let
    oldGraphStatements = graphStatements g
    oldDotNodes = nodeStmts oldGraphStatements
    oldDotEdges = edgeStmts oldGraphStatements
    (newDotNodes, newDotEdges) = (`runState` oldDotEdges) $ traverse relabel oldDotNodes
    newGraphStatements = oldGraphStatements
        { nodeStmts = newDotNodes
        , edgeStmts = newDotEdges
        }
  in
    g {graphStatements = newGraphStatements}

  where
    relabel :: DotNode GraphID -> State [DotEdge GraphID] (DotNode GraphID)
    relabel dotNode
      | hasStrLabel oldID = pure dotNode
      | otherwise = case findStrLabel dotNode of
                      Nothing  -> pure dotNode
                      Just txt -> do
                        let newID = Str txt
                        modify' (fmap (renameEdge oldID newID))
                        pure $ dotNode {nodeID = newID}

     where
       oldID = nodeID dotNode

       hasStrLabel :: GraphID -> Bool
       hasStrLabel (Str _) = True
       hasStrLabel _       = False

       findStrLabel :: DotNode n -> Maybe L.Text
       findStrLabel n = getFirst (foldMap getStrLabel (nodeAttributes n))

       getStrLabel :: Attribute -> First L.Text
       getStrLabel (Label (StrLabel txt)) = First . Just $ txt
       getStrLabel _                      = mempty

       renameEdge
         :: GraphID         -- ^ The original ID to be renamed
         -> GraphID         -- ^ The new ID name to be applied
         -> DotEdge GraphID -- ^ candidate edge
         -> DotEdge GraphID -- ^ Renamed edge
       renameEdge old new edge =
         edge
           { fromNode = newFromNode
           , toNode   = newToNode
           }

         where
           newToNode   | toNode edge   == old = new
                       | otherwise            = toNode edge
           newFromNode | fromNode edge == old = new
                       | otherwise            = fromNode edge


type EdgeIdentifier n = (n , n)


-- |
-- Takes a 'DotGraph' parse result and returns a set of unique node identifiers.
dotNodeSet :: Ord n => DotGraph n -> Set n
dotNodeSet = foldMap (S.singleton . nodeID) . graphNodes


-- |
-- Takes a 'DotGraph' parse result and returns a set of unique edge identifiers.
dotEdgeSet :: Ord n => DotGraph n -> Set (EdgeIdentifier n)
dotEdgeSet = foldMap (S.singleton . toEdgeIdentifier) . graphEdges
  where

    toEdgeIdentifier = fromNode &&& toNode


-- |
-- Takes a 'DotGraph' parse result and constructs a mapping from a node to it's
-- children.
dotChildMap :: Ord n => DotGraph n -> Map n (Set n)
dotChildMap = sharedWork directionality
  where
    directionality (k,v) = insertWith (<>) k (S.singleton v)


-- |
-- Takes a 'DotGraph' parse result and constructs a mapping from a node to it's
-- parents.
dotParentMap :: Ord n => DotGraph n -> Map n (Set n)
dotParentMap = sharedWork directionality
  where
    directionality (k,v) = insertWith (<>) v (S.singleton k)

-- |
-- Intelligently render a 'NodeLabel' of a 'GraphID' to a 'String' for output.
toIdentifier :: GraphID -> String
toIdentifier (Str x) = L.unpack x
toIdentifier (Num x) = show x


-- |
-- The shared work between generating the 'dotChildMap' and 'dotParentMap'
-- functions.
sharedWork
  :: forall n. Ord n
  => (EdgeIdentifier n -> Map n (Set n) -> Map n (Set n))
  -> DotGraph n
  -> Map n (Set n)
sharedWork logic dot = fromSet getAdjacency setOfNodes
  where
    -- Get the map of directed edges.
    -- Missing nodes with out degree 0.
    edgeMap      = foldr logic mempty . dotEdgeSet

    -- fold here has type :: Maybe (Set n) -> Set n
    -- returing the empty set in Nothing case.
    getAdjacency = fold . (`lookup` setOfEdges)

    setOfEdges   = edgeMap    dot

    setOfNodes   = dotNodeSet dot
