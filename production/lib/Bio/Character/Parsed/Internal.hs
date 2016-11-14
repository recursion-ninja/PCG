-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Character.Parsed.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Module holding the data type for a parsed character, which is the type
-- that comes from the parsers, and is then coverted into our various internal
-- character types
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleInstances, TypeSynonymInstances #-}

module Bio.Character.Parsed.Internal where

import           Data.Alphabet
import           Data.Foldable
import           Data.List.NonEmpty       (NonEmpty)
import qualified Data.List.NonEmpty as NE
import           Data.Vector              (Vector)
import qualified Data.Vector        as V
import           Data.Map                 (Map)
import           Test.QuickCheck


-- | An ordered dynamic character of ambiguity groups. This represents a dynamic
--   homology character when it comes from the parser (so is not yet encoded
---  or packed, if those are options.)
type ParsedChar = NonEmpty (AmbiguityGroup String)


-- | Represents a character sequence containing possibly missing character data.
type ParsedChars = Vector (Maybe ParsedChar)


-- TODO: Add a TaxonIdentifier or TerminalName as type string - lots of aliasing
-- | A mapping from taxon identifiers to thier corresponding sequences.
type TreeChars = Map String ParsedChars


-- | Higher level arbitrary helper
parsedCharsGivenAlph :: [Alphabet String] -> Gen ParsedChars
parsedCharsGivenAlph inAlphs = V.fromList <$> mapM parsedMaybe inAlphs


-- | Generates a maybe character
parsedMaybe :: Alphabet String -> Gen (Maybe ParsedChar)
parsedMaybe inAlph = do
    c <- arbParsedGivenAlph inAlph
    elements [Just c, Nothing]


-- | Define an arbitrary helper function to create a parsed sequence over an Alphabet
arbParsedGivenAlph :: Alphabet String -> Gen ParsedChar
arbParsedGivenAlph inAlph = NE.fromList <$> listOf1 ( NE.fromList <$> sublistOf (toList inAlph))

-- Shouldn't need this definition
{- -}
instance Arbitrary ParsedChar where
   arbitrary = do
       let amb = NE.fromList <$> listOf1 arbitrary
       NE.fromList <$> listOf1 amb
{- -}
