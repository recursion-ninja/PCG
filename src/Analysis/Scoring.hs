----------------------------------------------------------------------------
-- |
-- Module      :  Analysis.Scoring
-- Copyright   :  () 2015-2018 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# OPTIONS -fno-warn-incomplete-record-updates #-}

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies          #-}

module Analysis.Scoring
  (
  -- * Decoration
    performDecoration
  , scoreSolution
  -- * Decoration Removal
  , wipeNode
  , wipeScoring
  ) where

import           Analysis.Parsimony.Additive.Internal
import           Analysis.Parsimony.Dynamic.DirectOptimization
import           Analysis.Parsimony.Fitch.Internal
import           Analysis.Parsimony.Internal
import           Analysis.Parsimony.Sankoff.Internal
import           Bio.Character
import           Bio.Character.Decoration.Additive
import           Bio.Character.Decoration.Dynamic
import           Bio.Graph
import           Bio.Graph.Node
import           Bio.Graph.PhylogeneticDAG.Internal            (setDefaultMetadata)
import           Bio.Graph.ReferenceDAG.Internal
import           Bio.Sequence
import           Control.Lens.Operators                        ((%~))
import           Data.Default
import           Data.EdgeLength
import           Data.Function                                 ((&))
import qualified Data.List.NonEmpty                            as NE
import           Data.NodeLabel
import           Data.Vector                                   (Vector)


-- |
-- Remove all scoring data from nodes.
wipeScoring
  :: Default n
  => PhylogeneticDAG2 m e n u v w x y z
  -> PhylogeneticDAG2 m e n (Maybe u) (Maybe v) (Maybe w) (Maybe x) (Maybe y) (Maybe z)
wipeScoring (PDAG2 dag m) = PDAG2 wipedDAG m
  where
    wipedDAG =
      dag & _references %~ fmap wipeDecorations
          & _graphData  %~ setDefaultMetadata

    wipeDecorations
      :: Default n
      => IndexData e (PhylogeneticNode2 (CharacterSequence u v w x y z) n)
      -> IndexData e (PhylogeneticNode2 (CharacterSequence (Maybe u) (Maybe v) (Maybe w) (Maybe x) (Maybe y) (Maybe z)) n)
    wipeDecorations ind =
      ind & _nodeDecoration %~ wipeNode shouldWipe

      where
        shouldWipe = (not . null) . childRefs $ ind


-- |
-- Conditionally wipe the scoring of a single node.
wipeNode
  :: ( Default n
     )
  => Bool -- ^ Do I wipe?
  -> PhylogeneticNode2 (CharacterSequence        u         v         w         x         y         z ) n
  -> PhylogeneticNode2 (CharacterSequence (Maybe u) (Maybe v) (Maybe w) (Maybe x) (Maybe y) (Maybe z)) n
wipeNode wipe =
  PNode2 <$> pure . g . NE.head . resolutions <*> f . nodeDecorationDatum2
      where
        f :: Default a => a -> a
        f | wipe      = const def
          | otherwise = id

        g res = res & _characterSequence %~ hexmap h h h h h h

        h :: a -> Maybe a
        h | wipe      = const Nothing
          | otherwise = Just



-- |
-- Take a solution of one or more undecorated trees and assign preliminary and
-- final states to all nodes.
scoreSolution :: CharacterResult -> PhylogeneticSolution FinalDecorationDAG
scoreSolution (PhylogeneticSolution forests) = PhylogeneticSolution $ fmap performDecoration <$> forests


-- |
-- Take an undecorated tree and assign preliminary and final states to all nodes.
performDecoration
  :: ( DiscreteCharacterDecoration v StaticCharacter
     , DiscreteCharacterDecoration x StaticCharacter
     , DiscreteCharacterDecoration y StaticCharacter
     , RangedCharacterDecoration u ContinuousCharacter
     , RangedCharacterDecoration w StaticCharacter
     , SimpleDynamicDecoration z DynamicCharacter
     )
  => PhylogeneticDAG2 m EdgeLength NodeLabel (Maybe u) (Maybe v) (Maybe w) (Maybe x) (Maybe y) (Maybe z)
  -> FinalDecorationDAG
performDecoration x = performPreorderDecoration performPostorderDecoration
  where
    performPreorderDecoration
      :: PostorderDecorationDAG
          ( TraversalTopology
          , Double
          , Double
          , Double
          , Data.Vector.Vector (NE.NonEmpty TraversalFocusEdge)
          )
      -> FinalDecorationDAG
    performPreorderDecoration =
        preorderFromRooting
          adaptiveDirectOptimizationPreorder
          edgeCostMapping
          contextualNodeDatum
          minBlockContext

        . preorderSequence
          (const additivePreorder)
          (const fitchPreorder   )
          (const additivePreorder)
          (const sankoffPreorder )
          (const sankoffPreorder )
          (const extractPreNode  )
      where
        adaptiveDirectOptimizationPreorder meta decorationPreContext
          = directOptimizationPreorder pairwiseAlignmentFunction meta decorationPreContext
            where
              pairwiseAlignmentFunction = selectDynamicMetric meta

    performPostorderDecoration :: PostorderDecorationDAG (TraversalTopology, Double, Double, Double, Data.Vector.Vector (NE.NonEmpty TraversalFocusEdge))
    performPostorderDecoration = postorderResult

    (minBlockContext, postorderResult) = assignPunitiveNetworkEdgeCost post
    (post, edgeCostMapping, contextualNodeDatum) =
         assignOptimalDynamicCharacterRootEdges adaptiveDirectOptimizationPostorder
         . postorderSequence'
             (const (g' additivePostorder))
             (const (g' fitchPostorder))
             (const (g' additivePostorder))
             (g' . sankoffPostorder)
             (g' . sankoffPostorder)
             (g' . adaptiveDirectOptimizationPostorder)
         $ x

    g' :: (PostorderContext n c -> e) -> (PostorderContext (Maybe n) c -> e)
    g' postFn = \case
      LeafContext optD ->
        case optD of
          Nothing -> error "unitialized leaf node in PostorderBinaryContext!"
          Just d  -> postFn $ LeafContext d

      PostNetworkContext _ ->
        postFn $
          PostNetworkContext
            (error "The network internal node's data is used in the postorder!")
      postBin@PostBinaryContext {} ->
        postFn $
          postBin
          { binNode = error "A binary internal node's data is used in the postorder!"}

    adaptiveDirectOptimizationPostorder meta = directOptimizationPostorder pairwiseAlignmentFunction
      where
        pairwiseAlignmentFunction = selectDynamicMetric meta

{-
instance HasCharacterCost (Maybe u) Double where

    characterCost = lens (const 0) undefined


instance HasCharacterCost (Maybe u) Word where

    characterCost = lens (const 0) undefined
-}
