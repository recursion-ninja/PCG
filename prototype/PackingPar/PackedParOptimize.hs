{- Module for non-additive optimization of a bit packed tree-}
{-# LANGUAGE BangPatterns, DeriveGeneric, ConstraintKinds #-}
module PackingPar.PackedParOptimize (allOptimization, optimizeForest, getRootCost, costForest) where

-- imports 
import PackingPar.PackedBuild
import Component
import qualified Data.Vector as V
import qualified Packing.BitPackedNode as BN
import Control.Parallel.Strategies
import Control.DeepSeq
import Data.Maybe
import PackingPar.ParEnabledNode2
import qualified Data.Array.Accelerate as A
import Data.Bits

-- | Useful higher level data structures of trees, costs, etc
type TreeInfo a = (PhyloComponent, PackedTree a)
type ExpandTree a = (PhyloComponent, PackedTree a, PackedTree a)
type NewRows a = [(Int, ParEnabledNode a)]
type NewNodes = [(Int, V.Vector Float)]
type NodeCost = V.Vector Float

-- | Set up constraint shorthand
type Parable a = (Bits a, A.IsIntegral a, A.Elt a, Integral a, NFData a)

-- | Function to get the cost of an entire forest by map
costForest :: Parable a => PhyloForest -> (PackedForest a, PackedInfo a, ParPackMode) -> Float -> Int -> [Float]
costForest forestTrees (packForest, pInfo, pMode) weight parMode = 
    let 
        downOut = zipWith (\dat tree -> optimizationDownPass (tree, dat) pInfo pMode weight parMode) (V.toList packForest) forestTrees
        costs = map (\(tree, _, _) -> V.head $ getRootCost tree) downOut
    in costs

-- | Function to optimize an entire forest by a map
optimizeForest :: Parable a => PhyloForest -> (PackedForest a, PackedInfo a, ParPackMode) -> Float -> Int -> [TreeInfo a]
optimizeForest forestTrees (packForest, pInfo, pMode) weight parMode = zipWith (\dat tree -> allOptimization (tree, dat) pInfo pMode weight parMode) (V.toList packForest) forestTrees

-- | Unified function to perform both the first and second passes of fitch
allOptimization :: Parable a => TreeInfo a -> PackedInfo a -> ParPackMode -> Float -> Int -> TreeInfo a
allOptimization input pInfo pMode inWeight parMode = 
    let 
        downPass = optimizationDownPass input pInfo pMode inWeight parMode
        upPass = --trace ("down pass done " ++ show mat )
                    optimizationUpPass downPass pInfo pMode parMode
    in upPass

-- | Optimization down pass warpper for recursion from root
optimizationDownPass :: (Parable a) => TreeInfo a -> PackedInfo a -> ParPackMode -> Float -> Int -> ExpandTree a
optimizationDownPass (tree, mat) pInfo pMode inWeight parMode
    | (length $ children root) > 2 = error "Fitch algorithm only applies to binary trees" -- more than two children means fitch won't work
    | isTerminal root = -- if the root is a terminal, give the whole tree a cost of zero, do not reassign nodes
        let 
            newNode = modifyTotalCost root (V.singleton 0)
            newTree = (V.//) tree [(code root, newNode)]
        in (newTree, mat, mat)
    | (length $ children root) == 1 = -- if there is only one child, continue recursion down and resolve
        let 
            leftChild = head $ children root
            (nodes1, mRows1, fRows1) = internalDownPass (tree, mat) pInfo leftChild pMode inWeight parMode
            carryBit = snd $ head mRows1 -- with only one child, assignment and cost is simply carried up
            carryFBit = snd $ head fRows1
            carryCost = snd $ head nodes1
            newNodes = (code root, carryCost) : nodes1
            allMChanges = (code root, carryBit) : mRows1
            allFChanges = (code root, carryFBit) : fRows1
            combmat = combChanges allMChanges mat parMode
            fcombmat = combChanges allFChanges mat parMode
            combTree = combTreeChanges newNodes tree parMode
        in (combTree, combmat, fcombmat)
    | otherwise = -- if there are two children, do two recursive calls, get node assignment, and then resolve
        let 
            leftChild = head $ children root
            rightChild = head $ tail $ children root
            ((nodes1, mRows1, fRows1), (nodes2, mRows2, fRows2)) = parChildren (tree, mat) pInfo pMode inWeight leftChild rightChild parMode
            lbit = snd $ head mRows1
            rbit = snd $ head mRows2
            lcost = snd $ head nodes1
            rcost = snd $ head nodes2
            (mybit, myF, myCost) = downBitOps (lcost, lbit) (rcost, rbit) pInfo pMode inWeight
            treeUpdates = (code root, myCost) : (nodes1 ++ nodes2)
            allMChanges = (code root, mybit) : (mRows1 ++ mRows2) -- new bits always added to head to pass to bit ops
            allFRows = (code root, myF) : (fRows1 ++ fRows2)
            combmat = combChanges allMChanges mat parMode
            fcombmat = combChanges allFRows mat parMode
            combTree = combTreeChanges treeUpdates tree parMode
        in --trace ("new matrix " ++ show combmat)
            (combTree, combmat, fcombmat)

        where root = head $ [x | x <- (V.toList tree), isRoot x]

-- | Function to run children in parallel
parChildren :: Parable a => TreeInfo a -> PackedInfo a -> ParPackMode -> Float -> Int -> Int -> Int -> ((NewNodes, NewRows a, NewRows a), (NewNodes, NewRows a, NewRows a))
parChildren tInfo pInfo pMode inWeight leftChild rightChild parMode
    | parMode >= 1 = runEval $ do
        leftEval <- rpar (force (internalDownPass tInfo pInfo leftChild pMode inWeight parMode))
        rightEval <- rpar (force (internalDownPass tInfo pInfo rightChild pMode inWeight parMode))
        _ <- rseq leftEval
        _ <- rseq rightEval
        return (leftEval, rightEval)
    | otherwise = 
        let 
            left = internalDownPass tInfo pInfo leftChild pMode inWeight parMode
            right = internalDownPass tInfo pInfo rightChild pMode inWeight parMode
        in (left, right)


-- | Internal down pass that creates new rows without combining, making the algorithm faster
internalDownPass :: Parable a => TreeInfo a -> PackedInfo a -> Int -> ParPackMode -> Float -> Int -> (NewNodes, NewRows a, NewRows a)
--internalDownPass (tree, mat) pInfo myCode pMode | trace ("internal down pass with code " ++ show (mat V.! myCode)) False = undefined
internalDownPass (tree, mat) pInfo myCode pMode inWeight parMode
    | isTerminal node = --if it's a leaf, just vie cost zero and bounce up
        ([(myCode, (V.singleton 0))], [(myCode, mat V.! myCode)], [(myCode, mat V.! myCode)])
    | (length $ children node) > 2 = error "Fitch algorithm only works for binary trees"
    | (length $ parents node) > 1 = error "Fitch algorithm only works for trees, not networks" -- check for non-binary trees and networks
    | (length $ children node) == 1 = --if only one child, recurse down and carry the assignment
        let 
            leftChild = head $ children node
            (nodes1, mRows1, fRows1) = internalDownPass (tree, mat) pInfo leftChild pMode inWeight parMode
            carryBit = --trace ("carry bit " ++ show mRows1 ++ " and code " ++ show myCode)
                        snd $ head mRows1
            carryFBit = snd $ head fRows1
            carryCost = snd $ head nodes1
            newNodes = (myCode, carryCost) : nodes1
            allMChanges = (myCode, carryBit) : mRows1
            allFChanges = (myCode, carryFBit) : fRows1
        in (newNodes, allMChanges, allFChanges)
    | otherwise = -- if two children, do recursive calls and get node assignment
        let 
            leftChild = --trace ("children " ++ show (children node))
                        head $ children node
            rightChild = head $ tail $ children node
            ((nodes1, mRows1, fRows1), (nodes2, mRows2, fRows2)) = parChildren (tree, mat) pInfo pMode inWeight leftChild rightChild parMode
            lbit = snd $ head mRows1
            rbit = snd $ head mRows2
            lcost = snd $ head nodes1
            rcost = snd $ head nodes2
            (mybit, myF, myCost) = downBitOps (lcost, lbit) (rcost, rbit) pInfo pMode inWeight
            treeUpdates = (myCode, myCost) : (nodes1 ++ nodes2)
            allMChanges = (myCode, mybit) : (mRows1 ++ mRows2) -- new bits always added to head to pass to bit ops
            allFRows = (myCode, myF) : (fRows1 ++ fRows2)
        in (treeUpdates, allMChanges, allFRows)

        where node = tree V.! myCode

-- | Bit operations for the down pass: basically creats a mask for union and intersection areas and then takes them
-- returns the new assignment, the union/intersect mask, and the new total cost
downBitOps :: Parable a => (NodeCost, ParEnabledNode a) -> (NodeCost, ParEnabledNode a) -> PackedInfo a -> ParPackMode -> Float -> (ParEnabledNode a, ParEnabledNode a, NodeCost)
--downBitOps (lcost, lbit) (rcost, rbit) pInfo pMode weight | trace ("down bit ops with bit " ++ show lbit ++ " and right " ++ show rbit) False = undefined
downBitOps (lcost, lbit) (rcost, rbit) pInfo pMode inWeight =
    let
        notOr = complement $ lbit .&. rbit 
        union = --trace ("notOr " ++ show notOr)
                    lbit .|. rbit
        fBit = notOr .&. (snd $ masks pInfo)
        rightF = --trace ("fBit " ++ show fBit)
                    blockShiftAndFold "R" "&" notOr (blockLenMap pInfo) (length $ maxAlphabet pInfo) fBit
        finalF = blockShiftAndFold "L" "|" rightF (blockLenMap pInfo) (length $ maxAlphabet pInfo) rightF
        maskF = --trace ("mask "++ show (fst $ masks pInfo) ++ " and bit " ++ show finalF)
                    (fst $ masks pInfo) .&. finalF
        myCost = --trace ("in to cost " ++ show maskF)
                    getNodeCost maskF (blockLenMap pInfo) (length $ maxAlphabet pInfo)
        weightCost = inWeight * myCost
        newcost = V.singleton $ (V.head lcost) + (V.head rcost) + weightCost
        outbit = (maskF .&. union) .|. (lbit .&. rbit)
    in --trace ("finished bit ops " ++ show outbit)
        (outbit, maskF, newcost)

-- | Combines the changes made to two different matrices given a base matrix
-- assumes the same row isn't changed twice, which should never happen, so throws error if it does
combChanges :: (Parable a) => NewRows a -> PackedTree a -> Int -> PackedTree a
--combChanges changes initMat | trace ("combChanges with matrices "++ show changes) False = undefined
combChanges changes initMat parMode -- check for duplicates and throw an error
    | -1 `elem` (foldr (\(c, _) acc -> if c `elem` acc then -1 : c : acc else acc) [] changes) = error "multiple changes made to same node"
    | parMode >=2 = parVecUpdate initMat changes
    | otherwise = (V.//) initMat changes

-- | Combine changes to a tree from left and right children, multiple changes to the same node are not allowed
combTreeChanges :: NewNodes -> PhyloComponent -> Int -> PhyloComponent
combTreeChanges changes origTree parMode
    | -1 `elem` (foldr (\(c, _) acc -> if c `elem` acc then -1 : c : acc else acc) [] changes) = error "multiple changes made to same node"
    | parMode >= 2 = 
        let newNodes = map (\(index, cost) -> (index, modifyTotalCost (origTree V.! index) cost)) changes
        in parVecUpdate origTree newNodes
    | otherwise = 
        let newNodes = map (\(index, cost) -> (index, modifyTotalCost (origTree V.! index) cost)) changes
        in (V.//) origTree newNodes

-- | My update function evaluating in parallel
parVecUpdate :: V.Vector a -> [(Int, a)] -> V.Vector a
parVecUpdate initVec updates = 
    let 
        inFill = map (\i -> (i, initVec V.! i)) [0..(V.length initVec)-1]
        overFill = map(\(i, val) -> if isJust (elemTuple (i, val) updates) then fromJust (elemTuple (i, val) updates) else val) inFill `using` parListChunk 6 rpar 
    in V.fromList $ overFill

    where 
        elemTuple :: (Int, a) -> [(Int, a)] -> Maybe a
        elemTuple item list 
            | null match = Nothing
            | otherwise = Just (head match)
            where
                match = foldr (\(i, val) acc -> if i == (fst item) then val : acc else acc ) [] list

-- | Wrapper for up pass recursion to deal with root
optimizationUpPass :: (Parable a) => ExpandTree a -> PackedInfo a -> ParPackMode -> Int -> TreeInfo a
--optimizationUpPass (tree, mat, fmat) pInfo pMode | trace "up pass" False = undefined
optimizationUpPass (tree, mat, fmat) pInfo pMode parMode
    | isTerminal root = (tree, mat)
    | (length $ children root) > 2 = error "up pass cannot be performed for larger than binary trees" -- check for non-binary trees
    | (length $ children root) == 1 = -- for one child, recurse down and resolve changes
        let 
            leftCode = head $ children root
            leftChanges = internalUpPass (tree, mat, fmat) pInfo leftCode pMode parMode
            outmat = combChanges leftChanges mat parMode
        in (tree, outmat)
    | otherwise =  -- for two children, recurse down on both and resolve changes
        let 
            leftCode = head $ children root
            rightCode = head $ tail $ children root
            (leftChanges, rightChanges) = parUpPass (tree, mat, fmat) pInfo leftCode rightCode pMode parMode
            outmat = combChanges (leftChanges ++ rightChanges) mat parMode
        in (tree, outmat)

        where root = head $ [x | x <- (V.toList tree), isRoot x]

-- | Paralellized calls to internal up pass
parUpPass :: Parable a => ExpandTree a -> PackedInfo a -> Int -> Int -> ParPackMode -> Int -> (NewRows a, NewRows a)
parUpPass tInfo pInfo leftCode rightCode pMode parMode
    | parMode >= 1 = runEval $ do
        leftEval <- rpar (force (internalUpPass tInfo pInfo leftCode pMode parMode))
        rightEval <- rpar (force (internalUpPass tInfo pInfo rightCode pMode parMode))
        _ <- rseq leftEval
        _ <- rseq rightEval
        return (leftEval, rightEval)
    | otherwise = 
        let
            left = internalUpPass tInfo pInfo leftCode pMode parMode
            right = internalUpPass tInfo pInfo rightCode pMode parMode
        in (left, right)


-- | Internal up pass that performs most of the recursion
internalUpPass :: (Parable a) => ExpandTree a -> PackedInfo a -> Int -> ParPackMode -> Int -> NewRows a
--internalUpPass (tree, mat, fmat) pInfo myCode pMode | trace ("internal up pass ") False = undefined
internalUpPass (tree, mat, fmat) pInfo myCode pMode parMode
    | isTerminal (tree V.! myCode) = []
    | (length $ children $ (tree V.! myCode)) > 2 = error "up pass cannot be performed for larger than binary trees" -- check for non-binary
    | (length $ children $ (tree V.! myCode)) == 1 = --if one child, just recurse down
        let 
            node = tree V.! myCode
            leftCode = head $ children node
            leftChanges = internalUpPass (tree, mat, fmat) pInfo leftCode pMode parMode
        in leftChanges
    | otherwise = --of two children, determine the final assignment and then recurse down before resolving changes
        let 
            node = tree V.! myCode
            leftCode = head $ children node
            rightCode = head $ tail $ children node
            parentCode = head $ parents $ tree V.! myCode
            newBit = upPassBitOps (mat V.! parentCode) (mat V.! myCode) (mat V.! leftCode) (mat V.! rightCode) (fmat V.! myCode) pInfo
            passMat = (V.//) mat [(myCode, newBit)] 
            (leftChanges, rightChanges) = parUpPass (tree, passMat, fmat) pInfo leftCode rightCode pMode parMode
        in (myCode, newBit) : (leftChanges ++ rightChanges)

-- | Bit operations for the up pass
upPassBitOps :: (Parable a) => ParEnabledNode a -> ParEnabledNode a ->ParEnabledNode a -> ParEnabledNode a -> ParEnabledNode a -> PackedInfo a -> ParEnabledNode a
upPassBitOps pBit myBit lBit rBit fBit pInfo = 
    let 
        setX = (complement myBit) .&. pBit
        notX = complement setX
        setG = notX .&. (snd $ masks pInfo)
        rightG = blockShiftAndFold "R" "&" notX (blockLenMap pInfo) (length $ maxAlphabet pInfo) setG
        finalG = blockShiftAndFold "L" "|" rightG (blockLenMap pInfo) (length $ maxAlphabet pInfo) rightG
        maskedNotG = (fst $ masks pInfo) .&. (complement finalG)
        maskedNotF = (fst $ masks pInfo) .&. (complement fBit)
        setS = myBit .&. (pBit .|. maskedNotG)
        sndS = setS .|. (pBit .&. fBit)
        thdS = sndS .|. (maskedNotG .&. (maskedNotF .&. (pBit .&. (lBit .|. rBit))))
    in thdS

-- | Function to get the root cost of the tree
getRootCost :: PhyloComponent -> V.Vector Float
--getRootCost nodes | trace ("nodes " ++ show nodes) False = undefined
getRootCost nodes = 
    let root = head $ [x | x <- (V.toList nodes), isRoot x]
    in totalCost root