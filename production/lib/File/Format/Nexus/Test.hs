{-# LANGUAGE FlexibleContexts #-}

module File.Format.Nexus.Test
  ( testSuite
  ) where

import Control.Monad              (join)
import Data.Char
import Data.Either.Combinators    (isLeft,isRight)
import Data.Set                   (toList)
import File.Format.Nexus.Parser
import Test.Custom                (parseEquals,parseFailure,parseSuccess)
import Test.Tasty                 (TestTree,testGroup)
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Text.Megaparsec            (char,eof,parse)

import Debug.Trace (trace)

testSuite :: TestTree
testSuite = testGroup "Nexus Format"
  [ testGroup "Nexus Combinators" [ booleanDefinition'
                                  , stringDefinition'
                                  , quotedStringDefinition'
                                  , ignoredSubBlockDef'
                                  , notKeywordWord'
                                  , charFormatFieldDef'
                                  , formatDefinition'
                                  , stringListDefinition'] 
  ]

booleanDefinition' :: TestTree
booleanDefinition' = testGroup "booleanDefinition" [generalProperty]
  where
    generalProperty :: TestTree
    generalProperty = testProperty "General boolean flag structure" f
      where
        f x = null x
           || parse (booleanDefinition x <* eof) "" x == Right True

stringDefinition' :: TestTree
stringDefinition' = testGroup "stringDefinition" [generalProperty, withSpace, rejectsKeywords]
  where
    generalProperty = testProperty "General string definition: key=value, capture value" f
      where
        f :: (NonEmptyList AsciiAlphaNum, NonEmptyList AsciiAlphaNum) -> Bool
        f (x,y) = parse (stringDefinition key <* eof) "" str == Right val
          where
            key = getAsciiAlphaNum <$> getNonEmpty x
            val = getAsciiAlphaNum <$> getNonEmpty y
            str = key ++ "=" ++ val
    withSpace = testProperty "With 1 or more space characters after the =" f
      where
        f :: (NonEmptyList AsciiAlphaNum, NonEmptyList AsciiAlphaNum, NonEmptyList Whitespace) -> Bool
        f (x,y,z) = parse (stringDefinition key <* eof) "" str == Right val
          where
            key = getAsciiAlphaNum  <$> getNonEmpty x
            val = getAsciiAlphaNum  <$> getNonEmpty y
            spc = getWhitespaceChar <$> getNonEmpty z
            str = key ++ "=" ++ spc ++ val
    rejectsKeywords = testProperty "Rejects Keywords" f
      where
        f :: (NonEmptyList AsciiAlphaNum, NexusKeyword) -> Bool
        f (x,y) = isLeft $ parse (stringDefinition key <* eof) "" str
          where
            key = getAsciiAlphaNum <$> getNonEmpty x
            val = getNexusKeyword y
            str = key ++ "=" ++ val

quotedStringDefinition' :: TestTree
quotedStringDefinition' = testGroup "quotedStringDefinition" [generalProperty, missingCloseQuote, rejectsKeywords, withSpace]
  where
    badChars = "[;\""
    generalProperty = testProperty "General quoted string definition: key=\"space delimited values\", capture values" f
      where
        f :: (NonEmptyList AsciiAlphaNum, NonEmptyList Char) -> Bool
        f (x,y) = null res || parse (quotedStringDefinition key <* eof) "" str == Right (Right res)
          where
            key = getAsciiAlphaNum <$> getNonEmpty x
            val = filter (`notElem` badChars) $ getNonEmpty y
            res = words val
            str = key ++ "=\"" ++ val ++ "\""
            
    missingCloseQuote = testProperty "Missing close quote" f
      where
        f :: (NonEmptyList AsciiAlphaNum, NonEmptyList AsciiAlphaNum) -> Bool
        f (x,y) = (isLeft <$> parse (quotedStringDefinition key <* eof) "" str) == Right True
          where
            key = getAsciiAlphaNum <$> getNonEmpty x
            val = getAsciiAlphaNum <$> getNonEmpty y
            str = key ++ "=\"" ++ val
    rejectsKeywords = testProperty "Rejects keywords" f
      where
        f :: (NonEmptyList AsciiAlphaNum, NexusKeyword) -> Bool
        f (x,y) = isLeft $ parse (quotedStringDefinition key <* eof) "" str
          where
            key = getAsciiAlphaNum <$> getNonEmpty x
            val = getNexusKeyword y
            str = key ++ "=\"" ++ val ++ "\""
    withSpace = testProperty "With 1 or more space characters after the =" f
      where
        f :: (NonEmptyList AsciiAlphaNum, NonEmptyList Char, NonEmptyList Whitespace) -> Bool
        f (x,y,z) = null res || parse (quotedStringDefinition key <* eof) "" str == Right (Right res)
          where
            key = getAsciiAlphaNum  <$> getNonEmpty x
            val = filter (`notElem` badChars) $ getNonEmpty y
            res = words val
            spc = getWhitespaceChar <$> getNonEmpty z
            str = key ++ "=" ++ spc ++ "\"" ++ val ++ "\""

ignoredSubBlockDef' :: TestTree
ignoredSubBlockDef' = testGroup "ignoredSubBlockDef" [endTest, sendTest, semicolonTest, argumentTest, emptyStringTest]
    where
--        justDelimiter = tesCase
        endTest = testProperty "END;" f
            where
                f :: Bool
                f = isLeft $ parse (ignoredSubBlockDef ';' <* eof) "" "end;"
        sendTest = testProperty "Some word that ends with \"end;\"" f
            where
                f :: NonEmptyList AsciiAlphaNum -> Bool
                f x = parse (ignoredSubBlockDef ';' <* char ';' <* eof) "" inp == Right res
                    where
                        x' = (getAsciiAlphaNum <$> getNonEmpty x)
                        res = x' ++ "end"
                        inp = res ++ ";"
        semicolonTest = testProperty "Block ends with \";\"" f
            where
                f :: NonEmptyList AsciiAlphaNum -> Bool
                f x = parse (ignoredSubBlockDef ';' <* char ';' <* eof) "" inp == Right x'
                    where
                        x' = (getAsciiAlphaNum <$> getNonEmpty x)
                        inp = x' ++ ";"
        argumentTest = testProperty "Block ends with a designated delimiter" f
            where
                f :: (NonEmptyList AsciiAlphaNum, AsciiNonAlphaNum) -> Bool
                f (x,y) = parse (ignoredSubBlockDef arg <* char arg <* eof) "" inp == Right x'
                    where
                        arg = getAsciiNonAlphaNum y
                        x' = (getAsciiAlphaNum <$> getNonEmpty x)
                        inp = x' ++ [arg]
        emptyStringTest = testCase "Empty String" $ parseFailure (ignoredSubBlockDef ' ' <* eof) ";"

charFormatFieldDef' :: TestTree
charFormatFieldDef' = testGroup "charFormatFieldDef" ([emptyString] ++ testSingletons ++ testCommutivity)
    where
        emptyString = testCase "Empty String" $ parseEquals charFormatFieldDef "" []
        testSingletons = map (\(x,y) -> testCase x (parseEquals charFormatFieldDef x [y])) stringTypeList
        testCommutivity = map (\(x,y) -> testCase x (parseEquals charFormatFieldDef x y)) stringTypeListPerms 
        stringTypeList = [ ("datatype=xyz", CharDT "xyz")
                         , ("symbols=\"abc\"", SymStr (Right ["abc"]))
                         , ("transpose", Transpose True)
                         , ("interleave", Interleave True)
                         , ("tokens", Tokens True)
                         , ("equate=\"a={bc} d={ef}\"", EqStr (Right ["a={bc}", "d={ef}"]))
                         , ("missing=def", MissStr "def")
                         , ("gap=-", GapChar "-")
                         , ("matchchar=.", MatchChar ".")
                         , ("items=ghi", Items "ghi")
                         , ("respectcase", RespectCase True)
                         , ("nolabels", Unlabeled True)
                         , ("something ", IgnFF "something")
                         ]
        stringTypeListPerms = [(string ++ " " ++ string', [result, result']) | (string, result) <- stringTypeList, (string', result') <- stringTypeList]

stringListDefinition' :: TestTree
stringListDefinition' = testGroup "stringListDefinition" [test1, test2, rejectsKeywords]
    where
        test1 = testCase "Nothing between label and ;" $ parseEquals (stringListDefinition "label1") "label1;" []
        test2 = testCase "Label doesn't match" $ parseFailure (stringListDefinition "label2") "label1 abc;"
        rejectsKeywords = testProperty "Rejects Keywords" f
          where
            f :: (NonEmptyList AsciiAlphaNum, NexusKeyword) -> Bool
            f (x,y) = isLeft $ parse (stringListDefinition key <* eof) "" str
              where
                key = getAsciiAlphaNum <$> getNonEmpty x
                val = getNexusKeyword y
                str = key ++ " " ++ val ++ ";"

formatDefinition' :: TestTree
formatDefinition' = testGroup "formatDefinition" [test1, test2, test3, test4, test5, test6] 
    where
        test1 = testCase "transpose" $ parseEquals formatDefinition "format transpose;" $ CharacterFormat "" (Right [""]) (Right [""]) "" "" "" "" False False True False False
        test2 = testCase "datatype" $ parseEquals formatDefinition "format DATATYPE=Standard;" $ CharacterFormat "Standard" (Right [""]) (Right [""]) "" "" "" "" False False False False False
        test3 = testCase "symbols" $ parseEquals formatDefinition "format symbols=\"abcd\";" $ CharacterFormat "" (Right ["abcd"]) (Right [""]) "" "" "" "" False False False False False
        test4 = testCase "missing" $ parseEquals formatDefinition "format MISSING=?;" $ CharacterFormat "" (Right [""]) (Right [""]) "?" "" "" "" False False False False False
        test5 = testCase "gap" $ parseEquals formatDefinition "format GAP= -;" $ CharacterFormat "" (Right [""]) (Right [""]) "" "-" "" "" False False False False False
        test6 = testCase "all previous 5" $ parseEquals formatDefinition "FORMAT DATATYPE=Standard symbols=\"abcd\" MISSING=? GAP= - transpose;" $ CharacterFormat "Standard" (Right ["abcd"]) (Right [""]) "?" "-" "" "" False False True False False
        


notKeywordWord' :: TestTree
notKeywordWord' = testGroup "notKeywordWord" [rejectsKeywords, semicolonTest, withSpace, argumentTest]
  where
    rejectsKeywords = testProperty "Rejects keywords" f
      where
        -- f :: (NonEmptyList AsciiAlphaNum, NexusKeyword) -> Bool
        f x = isLeft $ parse (notKeywordWord "" <* eof) "" str
          where
            str = getNexusKeyword x
    semicolonTest = testProperty "Block ends with \";\", no argument" f
      where
        f :: NonEmptyList AsciiAlphaNum -> Bool
        f x = parse (notKeywordWord "" <* char ';' <* eof) "" inp == Right x'
            where
                x'  = getAsciiAlphaNum <$> getNonEmpty x
                inp = x' ++ ";"
    withSpace = testProperty "Input has spaces; return string to first space, no argument" f
      where
        f :: (NonEmptyList AsciiAlphaNum, Char) -> Bool
        f (x,y) = parse (notKeywordWord "" <* char ' ' <* char y <* eof) "" str == Right x'
          where
            x'  = getAsciiAlphaNum <$> getNonEmpty x
            str = x' ++ " " ++ [y]
    argumentTest = testProperty "Input ends with a designated delimiter" f
      where
        f :: (NonEmptyList AsciiAlphaNum, NonEmptyList Char) -> Bool
        f (x,y) = and $ fmap (\(anArg,inp) -> parse (notKeywordWord args <* char anArg <* eof) "" inp == Right x') inp'
          where
            x'   = getAsciiAlphaNum <$> getNonEmpty x
            args = filter (`notElem` x') $ getNonEmpty y
            inp' = [(n,m++[n]) | n <- args, m <- [x']]

stringTypeList = 
                 [ ("datatype=xyz", CharDT "xyz")
                 , ("symbols=\"abc\"", SymStr (Right ["abc"]))
                 , ("transpose", Transpose True)
                 , ("interleave", Interleave True)
                 , ("tokens", Tokens True)
                 , ("equate=\"a={bc} d={ef}\"", EqStr (Right ["a={bc}", "d={ef}"]))
                 , ("missing=def", MissStr "def")
                 , ("gap=-", GapChar "-")
                 , ("matchchar=.", MatchChar ".")
                 , ("items=ghi", Items "ghi")
                 , ("respectcase", RespectCase True)
                 , ("nolabels", Unlabeled True)
                 , ("something ", IgnFF "something")
                 ]
stringTypeListPerms = [(string ++ " " ++ string', [result, result']) | (string, result) <- stringTypeList, (string', result') <- stringTypeList]

newtype AsciiAlphaNum = AsciiAlphaNum { getAsciiAlphaNum :: Char } deriving (Eq)

newtype AsciiNonAlphaNum = AsciiNonAlphaNum { getAsciiNonAlphaNum :: Char } deriving (Eq)

newtype Whitespace = Whitespace { getWhitespaceChar :: Char } deriving (Eq)

nonSpaceChars = fmap AsciiAlphaNum . filter isAlphaNum $ chr <$> [0..128]

nonAlphaNumChars = fmap AsciiNonAlphaNum . filter (not . isAlphaNum) $ chr <$> [0..128]

whitespaceChars = fmap Whitespace " \t\n\r\f\v"

instance Arbitrary AsciiAlphaNum where
  arbitrary = elements nonSpaceChars

instance Show AsciiAlphaNum where
  show (AsciiAlphaNum c) = show c

instance Arbitrary AsciiNonAlphaNum where
  arbitrary = elements nonAlphaNumChars

instance Show AsciiNonAlphaNum where
  show (AsciiNonAlphaNum c) = show c

instance Arbitrary Whitespace where
  arbitrary = elements whitespaceChars

instance Show Whitespace where
  show (Whitespace c) = show c

newtype NexusKeyword = NexusKeyword String deriving (Eq)

instance Arbitrary NexusKeyword where
  arbitrary = elements . fmap NexusKeyword $ toList nexusKeywords

instance Show NexusKeyword where
  show (NexusKeyword c) = show c

getNexusKeyword (NexusKeyword c) = c