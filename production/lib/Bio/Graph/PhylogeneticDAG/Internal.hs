------------------------------------------------------------------------------
-- |
-- Module      :  Bio.Graph.PhylogeneticDAG.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Containing the master command for unifying all input types: tree, metadata, and sequence
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts #-}

module Bio.Graph.PhylogeneticDAG.Internal where

import           Bio.Character
import           Bio.Character.Decoration.Additive
import           Bio.Character.Decoration.Continuous
import           Bio.Character.Decoration.Discrete
import           Bio.Character.Decoration.Dynamic
import           Bio.Character.Decoration.Fitch
import           Bio.Character.Decoration.Metric 
import           Bio.Sequence
import           Bio.Sequence.Block        (CharacterBlock)
import           Bio.Graph
import           Bio.Graph.Node
import           Bio.Graph.ReferenceDAG.Internal
import           Control.Applicative       (liftA2)
import           Control.Evaluation
import           Data.Bits
import           Data.EdgeLength
import           Data.Foldable
--import           Data.Hashable
--import           Data.Hashable.Memoize
import           Data.IntSet               (IntSet)
import qualified Data.IntSet        as IS
import           Data.Key
import           Data.List.NonEmpty        (NonEmpty( (:|) ))
import qualified Data.List.NonEmpty as NE
import           Data.List.Utility
import           Data.Map                  (Map)
import           Data.Maybe
import           Data.MonoTraversable
import           Data.Semigroup
import           Data.Semigroup.Foldable
import           Data.Vector               (Vector)
import           Prelude            hiding (zipWith)


type SearchState = EvaluationT IO (Either TopologicalResult DecoratedCharacterResult)


type TopologicalResult = PhylogeneticSolution (ReferenceDAG () EdgeLength (Maybe String))


type CharacterResult = PhylogeneticSolution CharacterDAG


type DecoratedCharacterResult = PhylogeneticSolution FinalDecorationDAG


type UnRiefiedCharacterDAG =
       PhylogeneticDAG
         EdgeLength
         (Maybe String)
         UnifiedContinuousCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDynamicCharacter


type CharacterDAG =
       PhylogeneticDAG2
         EdgeLength
         (Maybe String)
         UnifiedContinuousCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDynamicCharacter


type PostOrderDecorationDAG =
       PhylogeneticDAG2
         EdgeLength
         (Maybe String)
         (ContinuousPostorderDecoration  ContinuousChar)
         (FitchOptimizationDecoration   StaticCharacter)
         (AdditivePostorderDecoration   StaticCharacter)
         (SankoffOptimizationDecoration StaticCharacter)
         (SankoffOptimizationDecoration StaticCharacter)
         (DynamicDecorationDirectOptimizationPostOrderResult DynamicChar)


type FinalDecorationDAG =
       PhylogeneticDAG2
         EdgeLength
         (Maybe String)
         (ContinuousOptimizationDecoration ContinuousChar)
         (FitchOptimizationDecoration   StaticCharacter)
         (AdditiveOptimizationDecoration StaticCharacter)
         (SankoffOptimizationDecoration StaticCharacter)
         (SankoffOptimizationDecoration StaticCharacter)
         (DynamicDecorationDirectOptimization DynamicChar)
--         (DynamicDecorationDirectOptimizationPostOrderResult DynamicChar)


type UnifiedCharacterSequence
     = CharacterSequence
         UnifiedContinuousCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDynamicCharacter


type UnifiedCharacterBlock
     = CharacterBlock
         UnifiedContinuousCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDiscreteCharacter
         UnifiedDynamicCharacter


type UnifiedContinuousCharacter = Maybe (ContinuousDecorationInitial ContinuousChar)


type UnifiedDiscreteCharacter   = Maybe (DiscreteDecoration StaticCharacter)


type UnifiedDynamicCharacter    = Maybe (DynamicDecorationInitial DynamicChar)


data PhylogeneticDAG e n u v w x y z
     = PDAG (ReferenceDAG () e (PhylogeneticNode n (CharacterSequence u v w x y z)))


data PhylogeneticDAG2 e n u v w x y z
     = PDAG2 ( ReferenceDAG
                 ( Map EdgeReference (ResolutionCache (CharacterSequence u v w x y z))
                 , Vector (Map EdgeReference (ResolutionCache (CharacterSequence u v w x y z)))
                 )
                 e
                 (PhylogeneticNode2 (CharacterSequence u v w x y z) n)
             )


instance ( Show e
         , Show n
         , Show u
         , Show v
         , Show w
         , Show x
         , Show y
         , Show z
         , HasBlockCost u v w x y z Word Double
         ) => Show (PhylogeneticDAG e n u v w x y z) where

    show (PDAG dag) = show dag <> "\n" <> foldMapWithKey f dag
      where
        f i (PNode n sek) = mconcat [ "Node {", show i, "}:\n\n", unlines [show n, show sek] ] 


instance ( Show e
         , Show n
         , Show u
         , Show v
         , Show w
         , Show x
         , Show y
         , Show z
         , HasBlockCost u v w x y z Word Double
         ) => Show (PhylogeneticDAG2 e n u v w x y z) where

    show p@(PDAG2 dag) = unlines
        [ renderSummary p
        , foldMapWithKey f dag
        ]
      where
--        f i (PNode2 n sek) = mconcat [ "Node {", show i, "}:\n\n", unlines [show n, show sek], "\n\n" ] 
        f i n = mconcat [ "Node {", show i, "}:\n\n", show n ]


renderSummary :: PhylogeneticDAG2 e n u v w x y z -> String
renderSummary (PDAG2 dag) = unlines
    [ show dag
    , show $ graphData dag
    ]


type EdgeReference = (Int, Int)


type IncidentEdges = [EdgeReference]

    
type Cost = Double


type ReRootedEdgeContext u v w x y z =
   ( ResolutionCache (CharacterSequence u v w x y z)
   , ResolutionCache (CharacterSequence u v w x y z)
   , ResolutionCache (CharacterSequence u v w x y z)
   )


applySoftwireResolutions :: [(ResolutionCache s, IntSet)] -> NonEmpty [ResolutionInformation s]
applySoftwireResolutions inputContexts =
    case inputContexts of
      []   -> pure []
      [x]  ->
          let y = pure <$> fst x
          -- TODO: review this logic thouroughly
          in  if   multipleParents x
              then y -- <> pure []
              else y
      x:y:_ -> pairingLogic (x,y)
  where
    multipleParents = not . isSingleton . otoList . snd
{-
    pairingLogic :: ( (ResolutionCache s), IntSet)
                    , (ResolutionCache s), IntSet)
                    )
                 -> NonEmpty [ResolutionInformation s]
-}
    pairingLogic (lhs, rhs) =
        case (multipleParents lhs, multipleParents rhs) of
          (False, False) -> pairedSet
          (False, True ) -> pairedSet <> lhsSet
          (True , False) -> pairedSet <> rhsSet
          (True , True ) -> pairedSet <> lhsSet <> rhsSet
       where
         lhsSet = pure <$> lhs'
         rhsSet = pure <$> rhs'
         lhs'   = fst lhs
         rhs'   = fst rhs
         pairedSet = 
             case cartesianProduct lhs' rhs' of
               x:xs -> {- NE.fromList . ensureNoLeavesWereOmmitted $ -} x:|xs
               []   -> error errorContext -- pure [] -- This shouldn't ever happen
           where
             errorContext = unlines
                 [ "The impossible happened!"
                 , "LHS:"
                 , shownLHS
                 , "RHS:"
                 , shownRHS
                 ]
               where
                 shownLHS = unlines . toList $ show . leafSetRepresentation <$> fst lhs
                 shownRHS = unlines . toList $ show . leafSetRepresentation <$> fst rhs

         cartesianProduct xs ys = 
             [ [x,y]
             | x <- toList xs
             , y <- toList ys
             , resolutionsDoNotOverlap x y
             ]
{-
           where
             xMask = foldMap1 leafSetRepresentation xs
             yMask = foldMap1 leafSetRepresentation ys
             overlapMask = xMask .&. yMask
             properOverlapInclusion x y =
               (leafSetRepresentation x .&. overlapMask) `xor` (leafSetRepresentation y .&. overlapMask) == zeroBits
-}


resolutionsDoNotOverlap :: ResolutionInformation a -> ResolutionInformation b -> Bool
resolutionsDoNotOverlap x y = leafSetRepresentation x .&. leafSetRepresentation y == zeroBits


localResolutionApplication :: HasBlockCost u v w x y d' Word Double
                           => (d -> [d] -> d')
                           -> NonEmpty (ResolutionInformation (CharacterSequence u v w x y d))
                           -> ResolutionCache (CharacterSequence u v w x y d)
                           -> NonEmpty (ResolutionInformation (CharacterSequence u v w x y d'))
localResolutionApplication f x y =
    liftA2 (generateLocalResolutions id2 id2 id2 id2 id2 f) mutalatedChild relativeChildResolutions
  where
    relativeChildResolutions = applySoftwireResolutions
        [ (x, IS.singleton 0)
        , (y, IS.singleton 0)
        ]
    id2 z _ = z
    mutalatedChild = pure
        ResInfo
        { totalSubtreeCost      = 0
        , localSequenceCost     = 0
        , subtreeEdgeSet        = mempty
        , leafSetRepresentation = zeroBits
        , subtreeRepresentation = singletonNewickSerialization (0 :: Word)
        , characterSequence     = characterSequence $ NE.head x
        }


generateLocalResolutions :: HasBlockCost u'' v'' w'' x'' y'' z'' Word Double
                         => (u -> [u'] -> u'')
                         -> (v -> [v'] -> v'')
                         -> (w -> [w'] -> w'')
                         -> (x -> [x'] -> x'')
                         -> (y -> [y'] -> y'')
                         -> (z -> [z'] -> z'')
                         ->  ResolutionInformation (CharacterSequence u   v   w   x   y   z  )
                         -> [ResolutionInformation (CharacterSequence u'  v'  w'  x'  y'  z' )]
                         ->  ResolutionInformation (CharacterSequence u'' v'' w'' x'' y'' z'')
generateLocalResolutions f1 f2 f3 f4 f5 f6 parentalResolutionContext childResolutionContext =
                ResInfo
                { totalSubtreeCost      = newTotalCost 
                , localSequenceCost     = newLocalCost
                , subtreeEdgeSet        = newSubtreeEdgeSet
                , leafSetRepresentation = newLeafSetRep
                , subtreeRepresentation = newSubtreeRep
                , characterSequence     = newCharacterSequence
                }
              where
                newTotalCost = sequenceCost newCharacterSequence

                newLocalCost = newTotalCost - sum (totalSubtreeCost <$> childResolutionContext)

                newCharacterSequence = transformation (characterSequence parentalResolutionContext) (characterSequence <$> childResolutionContext)
                newSubtreeEdgeSet    = foldMap subtreeEdgeSet childResolutionContext

                (newLeafSetRep, newSubtreeRep) =
                    case childResolutionContext of
                      []   -> (,) <$>          leafSetRepresentation <*>          subtreeRepresentation $ parentalResolutionContext
                      x:xs -> (,) <$> foldMap1 leafSetRepresentation <*> foldMap1 subtreeRepresentation $ x:|xs

                transformation pSeq cSeqs = hexZipWith f1 f2 f3 f4 f5 f6 pSeq transposition
                  where
                    transposition = 
                        case cSeqs of
                          x:xs -> hexTranspose $ x:|xs
                          []   -> let c = const []
                                  in hexmap c c c c c c pSeq


pairs :: Foldable f => f a -> [(a, a)]
pairs = f . toList
  where
    f    []  = []
    f   [_]  = []
    f (x:xs) = ((\y -> (x, y)) <$> xs) <> f xs


