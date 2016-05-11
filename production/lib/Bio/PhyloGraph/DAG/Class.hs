-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.PhyloGraph.DAG.Class
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Class for DAG representation
--
-----------------------------------------------------------------------------
{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies #-}

module Bio.PhyloGraph.DAG.Class where

import Data.Vector

-- | Accessor & mutator instance for types that expose nodes & edges.
class StandardDAG d n e | d -> n, d -> e where
    getNodes :: d -> Vector n
    setNodes :: d -> Vector n -> d
    getEdges :: d -> Vector e
    setEdges :: d -> Vector e -> d
    getRoot  :: d -> n 