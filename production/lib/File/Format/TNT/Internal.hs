{-# LANGUAGE DeriveFoldable, DeriveFunctor, DeriveTraversable, FlexibleContexts #-}
module File.Format.TNT.Internal where

import           Data.Char                (isSpace)
import           Data.List                (inits)
import           Data.List.NonEmpty       (NonEmpty)
import           Data.Maybe               (catMaybes)
import           Data.Vector              (Vector,fromList)
import           Text.Megaparsec
import           Text.Megaparsec.Custom
import           Text.Megaparsec.Lexer    (integer,number,signed)
import           Text.Megaparsec.Prim     (MonadParsec)

--Export types
{-
data Hennig
   = Hennig
   { taxaCount    :: Int
   , sequences    :: NonEmpty TaxonInfo
   , charMetaData :: Vector CharacterMetaData
   } deriving (Show)
-}

type TntResult = Either TreeOnly WithTaxa
type TreeOnly  = TRead
type Yucky     = String
data WithTaxa
   = WithTaxa
   { sequences    :: Vector TaxonInfo
   , charMetaData :: Vector CharacterMetaData
   , trees        :: [LeafyTree TaxonInfo]
   } deriving (Show)

-- CCode types
--------------------------------------------------------------------------------

data CCode
   = CCode
   { charState :: CharacterState
   , charSet   :: NonEmpty CharacterSet
   } deriving (Show)

data CharacterState
   = Additive
   | NonAdditive
   | Active
   | NonActive
   | Sankoff
   | NonSankoff
   | Weight Int
   | Steps  Int
   deriving (Show)

data CharacterSet
   = Single    Int
   | Range     Int Int
   | FromStart Int
   | ToEnd     Int
   | Whole
   deriving (Show)

-- CNames types
--------------------------------------------------------------------------------

type CNames = NonEmpty CharacterName

data CharacterName
   = CharacterName
   { sequenceIndex       :: Int
   , characterId         :: String
   , characterStateNames :: [String]
   } deriving (Show)

-- TRead types
--------------------------------------------------------------------------------

type TRead     = NonEmpty  TReadTree
type TReadTree = LeafyTree NodeType
type TNTTree   = LeafyTree TaxonInfo

data LeafyTree a
   = Leaf a
   | Branch [LeafyTree a]
   deriving (Foldable,Functor,Show,Traversable)

data NodeType
   = Index  Int
   | Name   String
   | Prefix String
   deriving (Show)

--XRead types
--------------------------------------------------------------------------------

data XRead
   = XRead
   { charCountx :: Int
   , taxaCountx :: Int
   , sequencesx :: NonEmpty TaxonInfo
   } deriving (Show)

-- | The sequence information for a taxon within the TNT file's XREAD command.
-- Contains the 'TaxonName' and the naive 'TaxonSequence' 
type TaxonInfo     = (TaxonName, TaxonSequence)

-- | The name of a taxon in a TNT file's XREAD command.
type TaxonName     = String

-- | The naive sequence of a taxon in a TNT files' XREAD command.
type TaxonSequence = [String]

-- CharacterMetaData types
--------------------------------------------------------------------------------

data CharacterMetaData
   = CharMeta
   { characterName   :: String
   , characterStates :: Vector String
   , additive        :: Bool --- Mutually exclusive sankoff
   , active          :: Bool
   , sankoff         :: Bool
   , weight          :: Int
   , steps           :: Int
   } deriving (Show)

initialMetaData :: CharacterMetaData
initialMetaData = CharMeta "" mempty False True False 1 1

metaDataTemplate :: CharacterState -> CharacterMetaData
metaDataTemplate state = modifyMetaDataState state initialMetaData

modifyMetaDataState :: CharacterState -> CharacterMetaData -> CharacterMetaData
modifyMetaDataState  Additive     old = old { additive = True , sankoff = False }
modifyMetaDataState  NonAdditive  old = old { additive = False }
modifyMetaDataState  Active       old = old { active   = True  }
modifyMetaDataState  NonActive    old = old { active   = False }
modifyMetaDataState  Sankoff      old = old { additive = False, sankoff = True  }
modifyMetaDataState  NonSankoff   old = old { sankoff  = False }
modifyMetaDataState (Weight n)    old = old { weight   = n     }
modifyMetaDataState (Steps  n)    old = old { steps    = n     }

modifyMetaDataNames :: CharacterName -> CharacterMetaData -> CharacterMetaData
modifyMetaDataNames charName old = old { characterName = characterId charName, characterStates = fromList $ characterStateNames charName }

-- | Parses an Int which is non-negative.
nonNegInt :: MonadParsec s m Char => m Int
nonNegInt = fromIntegral <$> integer

-- | Parses an positive integer from a variety of representations.
-- Parses both signed integral values and signed floating values
-- if the value is positive and an integer.
--
-- @flexiblePositiveInt labeling@ uses the @labeling@ parameter to
-- improve ParseError generation.
--
-- ==== __Examples__
--
-- Basic usage:
--
-- >>> parse (flexiblePositiveInt "errorCount") "" "1\n"
-- Right 1
--
-- >>> parse (flexiblePositiveInt "errorCount") "" "0\n"
-- Left 1:2:
-- expecting rest of number
-- The errorCount value (0) is not a positive number
--
-- >>> parse (flexiblePositiveInt "errorCount") "" "42.0\n"
-- Right 42
--
-- >>> parse (flexiblePositiveInt "errorCount") "" "0.1337\n"
-- Left 1:7:
-- expecting 'E', 'e', or rest of number
-- The errorCount value (0.1337) is a real value, not an integral value
-- The errorCount value (0.1337) is not a positive integer
flexiblePositiveInt :: MonadParsec s m Char => String -> m Int
flexiblePositiveInt labeling = either coerceIntegral coerceFloating
                             =<< signed whitespace number <?> ("positive integer for " ++ labeling)
  where
    coerceIntegral :: MonadParsec s m Char => Integer -> m Int
    coerceIntegral x
      | x <= 0      = fail $ concat ["The ",labeling," value (",show x,") is not a positive number"]
      | otherwise   = pure $ fromEnum x
    coerceFloating :: MonadParsec s m Char => Double -> m Int
    coerceFloating x
      | null errors = pure $ fromEnum rounded
      | otherwise   = fails errors
      where
        errors      = catMaybes [posError,intError]
        posError    = if x >= 1  then Nothing else Just $ concat ["The ",labeling," value (",show x,") is not a positive integer"]
        intError    = if isInt x then Nothing else Just $ concat ["The ",labeling," value (",show x,") is a real value, not an integral value"]
        isInt n     = n == fromInteger rounded
        rounded     = round x

-- | Consumes trailing whitespace after the parameter combinator.
symbol :: MonadParsec s m Char => m a -> m a
symbol c = c <* whitespace

-- | Consumes trailing whitespace after the parameter combinator.
trim :: MonadParsec s m Char => m a -> m a
trim c = whitespace *> c <* whitespace

-- | Consumes zero or more whitespace characters __including__ line breaks.
whitespace :: MonadParsec s m Char => m ()
whitespace = space

-- | Consumes zero or more whitespace characters that are not line breaks.
whitespaceInline :: MonadParsec s m Char => m ()
whitespaceInline =  inlineSpace

-- | Consumes a TNT keyword flexibly.
--   @keyword fullName minChars@ will parse the __longest prefix of__ @fullName@
--   requiring that __at least__ the first @minChars@ of @fullName@ are in the prefix.
--   Keyword prefixes are terminated with an `inlineSpace` which is not consumed by the combinator.
keyword :: MonadParsec s m Char => String -> Int -> m ()
keyword x y = abreviatable x y *> pure ()
  where
    abreviatable :: MonadParsec s m Char => String -> Int -> m String
    abreviatable fullName minimumChars =
      if minimumChars < 1
      then fail "Nonpositive abreviation prefix supplied to abreviatable combinator"
      else combinator <?> "keyword '" ++ fullName ++ "'"
      where
        thenInlineSpace = notFollowedBy notInlineSpace
        notInlineSpace  = satisfy (not . isSpace)
        (req,opt)       = splitAt minimumChars fullName
        tailOpts        = (\suffix -> try (string' (req ++ suffix) <* thenInlineSpace)) <$> inits opt
        combinator      = choice tailOpts *> pure fullName
