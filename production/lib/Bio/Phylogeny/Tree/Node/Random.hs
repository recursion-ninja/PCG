-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Phylogeny.Tree.Node.Random
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Module making Node an instance of Arbitrary for QuickCheck testing
--
-----------------------------------------------------------------------------

module Bio.Phylogeny.Tree.Node.Random where

import Bio.Phylogeny.Tree.Node
import Bio.Sequence.Coded
import Bio.Sequence.Random

import Data.Bits

import Test.Tasty.QuickCheck

instance Arbitrary b => Arbitrary (Node b) where
    arbitrary = do
        c <- arbitrary :: Gen Int
        root <- arbitrary :: Gen Bool
        leaf <- arbitrary :: Gen Bool
        child <- listOf $ (arbitrary :: Gen Int)
        parent <- listOf $ (suchThat arbitrary (not . (flip elem) child))
        seqs <- vectorOf 6 arbitrary 
        c2 <- arbitrary :: Gen Double
        return $ Node c root leaf child parent (seqs !! 0) (seqs !! 1) (seqs !! 2) (seqs !! 3) (seqs !! 4) (seqs !! 5) c2
