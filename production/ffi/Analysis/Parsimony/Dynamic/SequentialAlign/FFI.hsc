-----------------------------------------------------------------------------
-- |
-- TODO: Document module.
--
-----------------------------------------------------------------------------

{-# LANGUAGE BangPatterns, DeriveGeneric, FlexibleInstances, ForeignFunctionInterface, TypeSynonymInstances #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Analysis.Parsimony.Dynamic.SequentialAlign.FFI
  ( pairwiseSequentialAlignment
--  , sequentialAlign
--  , testFn
--  , main
  ) where

import Analysis.Parsimony.Dynamic.DirectOptimization.Pairwise (filterGaps)
import Bio.Character.Encodable
import Bio.Character.Exportable.Class
import Control.DeepSeq
import Data.Bits
import Data.Foldable
import Data.Monoid
import Data.TCM.Memoized.FFI
--import Data.Void
import Foreign         hiding (alignPtr)
--import Foreign.Ptr
--import Foreign.C.String
import Foreign.C.Types
import GHC.Generics           (Generic)
import System.IO.Unsafe
import Test.QuickCheck hiding ((.&.), output)

import Debug.Trace

-- #include "costMatrixWrapper.h"
-- #include "dynamicCharacterOperations.h"
#include "seqAlignInterface.h"
#include "seqAlignOutputTypes.h"
-- #include "seqAlignForHaskell.c"
#include <stdint.h>

-- |
-- A convient type alias for improved clairity of use.
type CArrayUnit  = CULong -- This will be compatible with uint64_t


coerceEnum :: (Enum a, Enum b) => a -> b
coerceEnum = toEnum . fromEnum



-- |
-- FFI call to the C pairwise alignment algorithm with /explicit/ sub & indel cost parameters.
{- foreign import ccall unsafe "seqAlignForHaskell aligner"
    call_aligner :: Ptr CDynamicChar -> Ptr CDynamicChar -> CInt -> CInt -> Ptr AlignResult -> CInt
-}
pairwiseSequentialAlignment :: (EncodableDynamicCharacter s, Exportable s, Show s) => MemoizedCostMatrix -> s -> s -> (s, Double, s, s, s)
pairwiseSequentialAlignment memo char1 char2 = unsafePerformIO $ do
--        !_ <- trace "Before constructing char1" $ pure ()
        char1'        <- constructCDynamicCharacterFromExportableCharacter char1
--        !_ <- trace "After  constructing char1" $ pure ()

--        !_ <- trace "Before constructing char2" $ pure ()
        char2'        <- constructCDynamicCharacterFromExportableCharacter char2
--        !_ <- trace "After  constructing char1" $ pure ()

--        !_ <- trace "Before mallocing result " $ pure ()
        resultPointer <- malloc :: IO (Ptr AlignResult)
--        !_ <- trace "After  mallocing result " $ pure ()

--        !_ <- trace ("Shown character 1: " <> show char1) $ pure ()
--        !_ <- trace ("Shown character 2: " <> show char2) $ pure ()

        !_ <- trace "Before FFI call" $ pure ()
        !_success     <- performSeqAlignfn_c char1' char2' (costMatrix memo) resultPointer
        !_ <- trace "After  FFI call" $ pure ()

--        _ <- free char1'
--        _ <- free char2'
        resultStruct  <- peek resultPointer
        let alignmentCost   = fromIntegral $ cost resultStruct
            resultElemCount = coerceEnum $ finalLength resultStruct
            bufferLength    = calculateBufferLength width resultElemCount
            buildExportable = ExportableCharacterSequence resultElemCount width
            generalizeFromBuffer = fromExportableBuffer . buildExportable
        !alignedChar1    <- fmap generalizeFromBuffer . peekArray bufferLength $ character1 resultStruct
        !alignedChar2    <- fmap generalizeFromBuffer . peekArray bufferLength $ character2 resultStruct
        !medianAlignment <- fmap generalizeFromBuffer . peekArray bufferLength $ medianChar resultStruct
        let !ungapped = filterGaps medianAlignment
--        _ <- free resultPointer
{--
        !_ <- trace ("Shown   gapped           : " <> show medianAlignment) $ pure ()
        !_ <- trace ("Shown ungapped           : " <> show ungapped       ) $ pure ()
        !_ <- trace ("Shown character 1 aligned: " <> show alignedChar1   ) $ pure ()
        !_ <- trace ("Shown character 2 aligned: " <> show alignedChar2   ) $ pure ()
--}
        !_ <- trace "Right Before Return" $ pure ()
        pure (ungapped, alignmentCost, medianAlignment, alignedChar1, alignedChar2)
    where
        width = exportedElementWidthSequence $ toExportableBuffer char1


constructCDynamicCharacterFromExportableCharacter :: Exportable s => s -> IO (Ptr CDynamicChar)
constructCDynamicCharacterFromExportableCharacter exChar = do
--        !_ <- trace (show exportableBuffer) $ pure ()
        valueBuffer <- newArray $ exportedBufferChunks exportableBuffer
        charPointer <- malloc :: IO (Ptr CDynamicChar)
        let charValue = CDynamicChar (coerceEnum width) (coerceEnum count) bufLen valueBuffer
        {-
            CDynamicChar
            { alphabetSizeChar = width
            , dynCharLen       = count
            , numElements      = bufLen
            , dynChar          = valueBuffer
            }
            -}
        !_ <- poke charPointer charValue
        pure charPointer
    where
        count  = exportedElementCountSequence exportableBuffer
        width  = exportedElementWidthSequence exportableBuffer
        bufLen = calculateBufferLength count width
        exportableBuffer = toExportableBuffer exChar

calculateBufferLength :: Enum b => Int -> Int -> b
calculateBufferLength count width = coerceEnum $ q + if r == 0 then 0 else 1
    where
        (q,r)  = (count * width) `divMod` finiteBitSize (undefined :: CULong)



foreign import ccall unsafe "seqAlignInteface performSequentialAlignment"
    performSeqAlignfn_c :: Ptr CDynamicChar
                        -> Ptr CDynamicChar
                        -> StablePtr ForeignVoid
                        -> Ptr AlignResult
                        -> IO CInt


-- |
-- The result of the alignment from the C side of the FFI
-- Includes a struct (actually, a pointer thereto), and that struct, in turn, has a string
-- in it, so Ptr CChar.
-- Modified from code samples here: https://en.wikibooks.org/wiki/Haskell/FFI#Working_with_C_Structures
data AlignResult
   = AlignResult
   { cost        :: CSize
   , finalLength :: CSize
   , character1  :: Ptr CArrayUnit
   , character2  :: Ptr CArrayUnit
   , medianChar  :: Ptr CArrayUnit
   }


-- | Because we're using a struct we need to make a Storable instance
instance Storable AlignResult where
    sizeOf    _ = (#size struct alignResult_t) -- #size is a built-in that works with arrays, as are #peek and #poke, below
    alignment _ = alignment (undefined :: CArrayUnit)
    peek ptr    = do -- to get values from the C app
        newCost <- (#peek struct alignResult_t, finalCost  ) ptr
        len     <- (#peek struct alignResult_t, finalLength) ptr
        char1   <- (#peek struct alignResult_t, finalChar1 ) ptr
        char2   <- (#peek struct alignResult_t, finalChar2 ) ptr
        med     <- (#peek struct alignResult_t, medianChar ) ptr
        pure AlignResult
             { cost        = newCost
             , finalLength = len
             , character1  = char1
             , character2  = char2
             , medianChar  = med
             }


------------- Don't need this part, but left in for completion ---------------
----- Will get compiler warning if left out, because of missing instances ----
    poke ptr (AlignResult costVal charLen char1Val char2Val medVal) = do -- to modify values in the C app
        (#poke struct alignResult_t, finalCost  ) ptr costVal
        (#poke struct alignResult_t, finalLength) ptr charLen
        (#poke struct alignResult_t, finalChar1 ) ptr char1Val
        (#poke struct alignResult_t, finalChar2 ) ptr char2Val
        (#poke struct alignResult_t, medianChar ) ptr medVal



-- |
-- Type of a dynamic character to pass back and forth across the FFI interface.
data CDynamicChar
   = CDynamicChar
   { alphabetSizeChar :: CSize
   , numElements      :: CSize
   , dynCharLen       :: CSize
   , dynChar          :: Ptr CArrayUnit
   }



-- | (✔)
instance Storable CDynamicChar where
    sizeOf    _ = (#size struct dynChar_t) -- #size is a built-in that works with arrays, as are #peek and #poke, below
    alignment _ = alignment (undefined :: CArrayUnit)
    peek ptr    = do -- to get values from the C app
        alphLen <- (#peek struct dynChar_t, alphSize  ) ptr
        nElems  <- (#peek struct dynChar_t, numElems  ) ptr
        seqLen  <- (#peek struct dynChar_t, dynCharLen) ptr
        seqVal  <- (#peek struct dynChar_t, dynChar   ) ptr
        pure CDynamicChar
             { alphabetSizeChar = alphLen
             , numElements      = nElems
             , dynCharLen       = seqLen
             , dynChar          = seqVal
             }
    poke ptr (CDynamicChar alphLen nElems seqLen seqVal) = do -- to modify values in the C app
        (#poke struct dynChar_t, alphSize  ) ptr alphLen
        (#poke struct dynChar_t, numElems  ) ptr nElems
        (#poke struct dynChar_t, dynCharLen) ptr seqLen
        (#poke struct dynChar_t, dynChar   ) ptr seqVal



{-
-- |
-- FFI call to the C pairwise alignment algorithm with /defaulted/ sub & indel cost parameters
foreign import ccall unsafe "exportCharacter testFn"
    callExtFn_c  :: Ptr CDynamicChar -> Ptr CDynamicChar -> Ptr AlignResult -> CInt
-}




{-
-- |
-- testFn can be called from within Haskell code.
testFn :: CDynamicChar -> CDynamicChar -> Either String (Int, String)
testFn char1 char2 char3 = unsafePerformIO $
    -- have to allocate memory. Note that we're allocating via a lambda fn. In use, the lambda will take whatever is the
    -- argument of testFn, but here there is no argument, so all allocation is hard-coded.
    alloca $ \alignPtr -> do
        marshalledChar1 <- new char1
        marshalledChar2 <- new char2
        marshalledChar3 <- new char3
        print marshalledChar1
        -- Using strict here because the values need to be read before freeing,
        -- so lazy is dangerous.
        let !status = callExtFn_c marshalledChar1 marshalledChar2 alignPtr

        -- Now checking return status. If 0, then all is well, otherwise throw an error.
        if status == (0 :: CInt)
            then do
                AlignResult cost seqLen seqVal <- peek alignPtr
                seqFinalVal                    <- peekArray (fromIntegral seqLen) seqVal
                free seqVal
                pure $ Right (fromIntegral cost, show seqFinalVal)
            else do
                pure $ Left "Out of memory"

-}

{-
-- Just for testing from CLI outside of ghci.
-- | A test driver for the FFI functionality
main :: IO ()
main = do
    char1 <- generate (arbitrary :: Gen CDynamicChar)
    --char2 <- generate (arbitrary :: Gen CDynamicChar)
    print char1
    --print char2
    print $ testFn char1 char1
-}
