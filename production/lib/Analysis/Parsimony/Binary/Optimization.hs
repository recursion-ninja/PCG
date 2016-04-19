-----------------------------------------------------------------------------
-- |
-- Module      :  Analysis.Parsimony.Binary.Optimization
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- General wrapper for all forms of optimization on binary trees
--
-----------------------------------------------------------------------------

{-# LANGUAGE AllowAmbiguousTypes, ConstraintKinds, FlexibleContexts #-}

module Analysis.Parsimony.Binary.Optimization where

import Analysis.Parsimony.Binary.Internal
import Analysis.Parsimony.Binary.Fitch
import Analysis.Parsimony.Binary.DirectOptimization
--import Analysis.Parsimony.Binary.SequentialAlign

import Data.Maybe
import Data.Vector (Vector, ifoldr, (!))
import Data.Monoid

import Bio.PhyloGraph.Forest
import Bio.PhyloGraph.Network
import Bio.PhyloGraph.Solution.Class
import Bio.PhyloGraph.Solution.Metadata
import Bio.PhyloGraph.Tree.Binary
import Bio.PhyloGraph.Tree.Rose
import Bio.PhyloGraph.Node ()
import Bio.PhyloGraph.Node.Final
import Bio.PhyloGraph.Node.Preliminary
import Bio.PhyloGraph.Node.Encoded ()
import Bio.Metadata

--import Debug.Trace

-- | Top level binary optimization wrapper to optimize over a solution
-- Takes in an overall weight and a solution
-- Returns a solution with any relevant values assigned (root cost, node assignments, etc. depending on optimization types)
solutionOptimization :: SolutionConstraint' r f t n s m => Double -> r -> r
solutionOptimization weighting inSolution = setForests inSolution $ fmap (graphOptimization weighting meta) (getForests inSolution)
    where
        meta = metadata inSolution

-- | Mapping function to optimize over a forest
-- Takes in an overall weight, a vector of metadata, and a forest
-- Returns a forest with relevant values assigned
graphOptimization :: (ForestConstraint' f t n s, Metadata m s) => Double -> Vector m -> f -> f
graphOptimization weighting meta inGraph = setTrees inGraph $ fmap (allOptimization weighting meta) (trees inGraph)

-- | Unified function to perform both the preorder and postorder passes (as relevant)
-- Takes in an overall weight, a vector of metadata, and a tree
-- Returns a tree with values assigned
allOptimization :: (TreeConstraint' t n s, Metadata m s) => Double -> Vector m -> t -> t
--allOptimization _ inTree | trace ("allOptimization " ++ show (names inTree IM.! 63)) False = undefined
allOptimization weighting meta inTree =
    let
        downPass = optimizationPreorder weighting inTree meta
        upPass = optimizationPostorder downPass meta
    in upPass

-- | Optimization preorder wrapper to perform relevant algorithm at all nodes
-- Takes in an overall weight, a tree, and a vector of metadata
-- Returns a tree with values assigned
-- Correctly handles roots, leaves, and nodes with only one child
optimizationPreorder :: (TreeConstraint' t n s, Metadata m s) => Double -> t -> Vector m -> t
optimizationPreorder weighting tree meta
    | isLeaf (root tree) tree = -- if the root is a terminal, give the whole tree a cost of zero, do not reassign nodes
        let
            newNode = setLocalCost 0.0 $ setTotalCost 0.0 (root tree)
            newTree = tree `update` [newNode]
        in newTree
    | leftOnly && rightOnly = tree 
    | rightOnly = -- if there is only one child, continue recursion down and resolve
        let
            nodes1 = internalPreorder weighting (fromJust $ rightChild (root tree) tree) tree meta -- with only one child, assignment and cost is simply carried up
            carryNode = head nodes1
            newNodes = (setTemporary (getTemporary carryNode) $ setAlign (getPreliminaryAlign carryNode)
                        $ setPreliminary (getPreliminary carryNode) $ setTotalCost (getTotalCost carryNode) $ setLocalCost (getLocalCost carryNode) (root tree)) : nodes1
        in tree `update` newNodes
    | leftOnly =
        let
            nodes1 = internalPreorder weighting (fromJust $ leftChild (root tree) tree) tree meta -- with only one child, assignment and cost is simply carried up
            carryNode = head nodes1
            myNode = setTemporary (getTemporary carryNode) $ setAlign (getPreliminaryAlign carryNode)
                        $ setPreliminary (getPreliminary carryNode) $ setTotalCost (getTotalCost carryNode) $ setLocalCost (getLocalCost carryNode) (root tree)
            newNodes = myNode : nodes1
        in tree `update` newNodes
    | otherwise =
        let
            nodes1 = internalPreorder weighting (fromJust $ rightChild (root tree) tree) tree meta
            nodes2 = internalPreorder weighting (fromJust $ leftChild (root tree) tree) tree meta
            myNode = preorderNodeOptimize weighting (root tree) (head nodes1) (head nodes2) meta
            newNodes = myNode : (nodes1 ++ nodes2)
        in tree `update` newNodes

        where
            leftOnly  = isNothing $ rightChild (root tree) tree
            rightOnly = isNothing $ leftChild  (root tree) tree

-- | Internal preorder optimization pass
-- takes in a weight, a current node, a tree, and a vector of metadata
-- returns a list of nodes that have had changes applied to them
-- By using this node accumulation scheme, we save some complexity over simply always dealing with a tree
internalPreorder :: (TreeConstraint' t n s, Metadata m s) => Double -> n -> t -> Vector m -> [n]
internalPreorder weighting node tree meta
    | isLeaf node tree = -- if the root is a terminal, give the whole tree a cost of zero, do not reassign nodes
        let newNode = setTotalCost 0.0 $ setLocalCost 0.0 node
        in [newNode]
    | rightOnly && leftOnly = [] --error "Problem with binary tree structure: non-terminal has no children"
    | rightOnly = -- if there is only one child, continue recursion down and resolve
        let
            nodes1 = internalPreorder weighting (fromJust $ rightChild node tree) tree meta -- with only one child, assignment and cost is simply carried up
            carryNode = head nodes1
            myNode = setTemporary (getTemporary carryNode) $ setAlign (getPreliminaryAlign carryNode)
                        $ setPreliminary (getPreliminary carryNode) $ setTotalCost (getTotalCost carryNode) $ setLocalCost (getLocalCost carryNode) node
        in myNode : nodes1
    | leftOnly =
        let
            nodes1 = internalPreorder weighting (fromJust $ leftChild node tree) tree meta -- with only one child, assignment and cost is simply carried up
            carryNode = head nodes1
            myNode = setTemporary (getTemporary carryNode) $ setAlign (getPreliminaryAlign carryNode)
                        $ setPreliminary (getPreliminary carryNode) $ setTotalCost (getTotalCost carryNode) $ setLocalCost (getLocalCost carryNode) node
        in myNode : nodes1
    | otherwise =
        let

            nodes1 = internalPreorder weighting (fromJust $ rightChild node tree) tree meta
            nodes2 = internalPreorder weighting (fromJust $ leftChild node tree) tree meta
            myNode = preorderNodeOptimize weighting node (head nodes1) (head nodes2) meta
        in myNode : (nodes1 ++ nodes2)

        where
            leftOnly  = isNothing $ rightChild node tree
            rightOnly = isNothing $ leftChild node tree

-- | Wrapper for the postorder
-- Takes in a tree and a vector of metadata
-- returns a tree with relevant nodes assigned
-- This wrapper allows us to deal correctly with root passing to postorder algorithms
optimizationPostorder :: (TreeConstraint' t n s, Metadata m s) => t -> Vector m -> t
optimizationPostorder tree meta
    | isLeaf (root tree) tree = tree
    | rightOnly && leftOnly = tree --error "Problem with binary tree structure: non-terminal has no children"
    | rightOnly =
        let nodes1 = internalPostorder (fromJust $ rightChild (root tree) tree) tree meta
        in tree `update` nodes1
    | leftOnly =
        let nodes1 = internalPostorder (fromJust $ leftChild (root tree) tree) tree meta
        in tree `update` nodes1
    | otherwise =
        let
            nodes1 = internalPostorder (fromJust $ rightChild (root tree) tree) tree meta
            nodes2 = internalPostorder (fromJust $ leftChild (root tree) tree) tree meta
        in tree `update` (nodes1 ++ nodes2)

        where
            leftOnly  = isNothing $ rightChild (root tree) tree
            rightOnly = isNothing $ leftChild (root tree) tree

-- | Internal postorder pass that does the main recursion
-- Takes in a current node, the tree, and a vector of metadata
-- returns a list of nodes that have been updated.
-- As in the preorder, this method saves on some time complexity
internalPostorder :: (TreeConstraint' t n s, Metadata m s) => n -> t -> Vector m -> [n]
internalPostorder node tree meta
    | isLeaf node tree = []
    | rightOnly && leftOnly = [] 
    | rightOnly = internalPostorder (fromJust $ rightChild node tree) tree meta
    | leftOnly  = internalPostorder (fromJust $ leftChild node tree) tree meta
    | otherwise =
        let newNode = postorderNodeOptimize node (fromJust $ leftChild node tree) (fromJust $ rightChild node tree) (parent node tree) meta
            nodes1  = internalPostorder (fromJust $ rightChild node tree) tree meta
            nodes2  = internalPostorder (fromJust $ leftChild node tree) tree meta
        in newNode : (nodes1 ++ nodes2)

        where
            leftOnly  = isNothing $ rightChild node tree
            rightOnly = isNothing $ leftChild node tree


-- | Wrapper function to preform optimization on a node during the preorder pass
-- Essentially a map over a decision function that selects and performs the right optimization for each character.
-- Takes in an overall weight, a current node, the left child, the right child, and a vector of metadata
-- Outputs a node with the correct sequences and costs assigned
preorderNodeOptimize :: (NodeConstraint' n s, Metadata m s) => Double -> n -> n -> n -> Vector m -> n
preorderNodeOptimize weighting curNode lNode rNode meta = setTotalCost summedTotalCost res
    where
        summedTotalCost = sum $ getTotalCost <$> [res,lNode,rNode] --getTotalCost res + getTotalCost lNode + getTotalCost rNode
        res             = ifoldr chooseOptimization curNode meta

        --chooseOptimization :: (NodeConstraint' n s, Metadata m s) => Int -> m -> n -> n
        chooseOptimization curPos curCharacter setNode
            -- TODO: Compiler error maybe below with comment structuers and 'lets'
            | getIgnored curCharacter = setNode
            | getType curCharacter == Fitch =
                let (assign, temp, local) = preorderFitchBit curWeight (getForAlign lNode ! curPos) (getForAlign rNode ! curPos) curCharacter
                in addTemporary temp $ addLocalCost (local * curWeight * weighting) $ addTotalCost (local * curWeight * weighting) $ addAlign assign $ addPreliminary assign setNode
            | getType curCharacter == DirectOptimization =
                let (ungapped, cost, gapped, _, _) = naiveDO (getForAlign lNode ! curPos) (getForAlign rNode ! curPos) curCharacter
                in addLocalCost (cost * curWeight * weighting) $ addTotalCost (cost * curWeight * weighting) $ addAlign gapped $ addPreliminary ungapped setNode
            | otherwise = error "Unrecognized optimization type"

                where curWeight = getWeight curCharacter

                -- getForAlign returns a node, either encoded, getPreliminary or getPreliminary align. It's in Analysis.Parsimony.Binary.Internal
                -- the return type is a vector of encoded sequences,
                -- where an EncodedSeq (encoded sequence) is a maybe vector of some type from Bio/Sequence/Coded.hs
                --let (ungapped, cost, gapped, leftGapped, rightGapped) = sequentialAlign (getForAlign lNode ! curPos) (getForAlign rNode ! curPos)
                --in  addLocalCost cost $ addTotalCost cost $ addAlign gapped $ addPreliminary ungapped setNode

        addPreliminary addVal inNode = addToField setPreliminary getPreliminary      addVal inNode
        addAlign       addVal inNode = addToField setAlign       getPreliminaryAlign addVal inNode
        addTemporary   addVal inNode = addToField setTemporary   getTemporary        addVal inNode
        addTotalCost   addVal node   = setTotalCost (addVal + getTotalCost node) node
        addLocalCost   addVal node   = setLocalCost (addVal + getLocalCost node) node

-- | addToField takes in a setter fn, a getter fn, a value and a node.
-- It then gets the related value from the node, adds to it the passed value,
-- and sets that value on the node. It returns a new node with the newly computed value set.
addToField :: NodeConstraint' n s => (Vector s -> n -> n) -> (n -> Vector s) -> s -> n -> n
addToField setter getter val node = setter (pure val <> getter node) node

-- | Wrapper function to preform optimization on a node during the postorder pass
-- As in the preorder, it selects an optimization for each character, then groups it together and assigns to the node
-- Takes in a current node, left child, right child, parent node, and vector of metadata
-- returns a node with everything assigned
postorderNodeOptimize :: (NodeConstraint' n s, Metadata m s) => n -> n -> n -> Maybe n -> Vector m -> n
postorderNodeOptimize curNode lNode rNode pNode meta
    | isNothing pNode = error "No parent node on postorder traversal"
    | otherwise       = ifoldr chooseOptimization curNode meta
    where
        --chooseOptimization :: (NodeConstraint' n s, Metadata m s) => Int -> m -> n -> n
        chooseOptimization i curCharacter setNode
            | getType curCharacter == Fitch =
                let finalAssign = postorderFitchBit (getForAlign curNode ! i) (getForAlign lNode ! i) (getForAlign rNode ! i) (getForAlign (fromJust pNode) ! i) (getTemporary curNode ! i) curCharacter
                in addToField setFinal getFinal finalAssign setNode
            | getType curCharacter == DirectOptimization =
                let (final, _, _, _, _) = naiveDO (getForAlign curNode ! i) (getForAlign (fromJust pNode) ! i) curCharacter
                in addToField setFinal getFinal final setNode
            | otherwise = error "Unrecognized optimization type"
