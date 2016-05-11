-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.PhyloGraph.Network.Class
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Class with operations on a network and a node inside it
--
-----------------------------------------------------------------------------

{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies #-}
module Bio.PhyloGraph.Network.Class where

-- | A network holds topological information as well as the ability to update based on a list of nodes
class Monoid t => Network t n | t -> n where
    parents :: n -> t -> [n] 
    children :: n -> t -> [n]
    root :: t -> n
    nodeIsLeaf :: n -> t -> Bool
    nodeIsRoot :: n -> t -> Bool
    update :: t -> [n] -> t
    numNodes :: t -> Int
    addNode :: t -> n -> t
    -- TODO add tree breaking at node, delete node, cut tree at condition, delete edge, delete edges, add edge
