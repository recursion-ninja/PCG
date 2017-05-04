
{-# LANGUAGE FlexibleContexts #-}

module Test.Custom.DynamicCharacterNode
  ( DynamicCharacterNode()
  , getDynamicCharacterDecoration
  , constructNode
  ) where


import           Analysis.Parsimony.Dynamic.DirectOptimization
import           Analysis.Parsimony.Dynamic.DirectOptimization.Pairwise (filterGaps)
import           Bio.Character
import           Bio.Character.Decoration.Dynamic
import           Data.Alphabet.IUPAC
import           Data.MonoTraversable
import           Data.String
import           Test.Custom.NucleotideSequence
import           Test.QuickCheck


newtype DynamicCharacterNode = DCN
    { getDynamicCharacterDecoration :: DynamicDecorationDirectOptimization DynamicChar
    }
    deriving (Show)


instance Arbitrary DynamicCharacterNode where

    arbitrary = do
        lhs <- (unwrap <$> arbitrary) `suchThat` isNotAllGaps
        rhs <- (unwrap <$> arbitrary) `suchThat` isNotAllGaps
        pure . DCN $ constructNode lhs rhs
      where
        isNotAllGaps  = not . onull . filterGaps
        unwrap (NS x) = x


constructNode :: DynamicChar -> DynamicChar -> DynamicDecorationDirectOptimization DynamicChar
constructNode lhs rhs = directOptimizationPreOrder pairwiseFunction lhsDec [(0,rootDec)]
  where
    lhsDec  = toLeafNode $ initDec lhs
    rhsDec  = toLeafNode $ initDec rhs
    rootDec = toRootNode lhsDec rhsDec


toLeafNode :: ( Show (Element c)
              , Integral (Element c)
              , SimpleDynamicDecoration d c
              )
           => d -> DynamicDecorationDirectOptimizationPostOrderResult c
toLeafNode c = directOptimizationPostOrder pairwiseFunction c []


toRootNode :: DynamicDecorationDirectOptimizationPostOrderResult DynamicChar
           -> DynamicDecorationDirectOptimizationPostOrderResult DynamicChar
           -> DynamicDecorationDirectOptimization DynamicChar
toRootNode x y = directOptimizationPreOrder pairwiseFunction z []
  where
    z :: DynamicDecorationDirectOptimizationPostOrderResult DynamicChar 
    z = directOptimizationPostOrder pairwiseFunction e [x,y]
    e :: DynamicDecorationDirectOptimizationPostOrderResult DynamicChar
    e = undefined


pairwiseFunction :: ( Integral (Element s)
                    , Show (Element s)
                    , EncodableDynamicCharacter s
                    ) => s -> s -> (Word, s, s, s, s)
pairwiseFunction x y = naiveDO x y scm


scm :: Word -> Word -> Word
scm i j = if i == j then 0 else 1


initDec :: DynamicChar -> DynamicDecorationInitial DynamicChar
initDec = toDynamicCharacterDecoration name weight alphabet scm id
  where
    name   = fromString "Test Character"
    weight = 1
    alphabet = fromSymbols ["A","C","G","T"] 


