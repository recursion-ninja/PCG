-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.PhyloGraph.Node.Referential
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Class for nodes that store their code
--
-----------------------------------------------------------------------------

module Bio.PhyloGraph.Node.Referential where

class RefNode n where
    getCode :: n -> Int