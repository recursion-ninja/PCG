-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Graph.TopologyRepresentation
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Set-like structures for collection of edges.
--
-----------------------------------------------------------------------------

{-# LANGUAGE DeriveGeneric, GeneralizedNewtypeDeriving #-}

module Bio.Graph.TopologyRepresentation
  ( TopologyRepresentation(..)
  , singleNetworkEdge
  ) where


import           Control.DeepSeq
import           Data.EdgeSet
import           Data.Semigroup
import           GHC.Generics       (Generic)


-- |
-- Represents a collection of network edges.
--
-- Often used to represent a unique spanning tree in a phylogenetic DAG.
newtype TopologyRepresentation e = TR (EdgeSet e)
  deriving (Eq, Foldable, Generic, Monoid, Ord, Semigroup)


instance NFData e => NFData (TopologyRepresentation e) where

    rnf (TR x) = rnf x


-- |
-- Construct a singleton 'EdgeSet' value. Use the semigroup operator '(<>)' to
-- construct larger a 'EdgeSet'. This enforces the non-empty invariant of the
-- 'EdgeSet' data-structure.
singleNetworkEdge :: e -> TopologyRepresentation e
singleNetworkEdge = TR . singletonEdgeSet