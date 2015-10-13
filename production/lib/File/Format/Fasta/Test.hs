{-# LANGUAGE BangPatterns, FlexibleContexts #-}

module File.Format.Fasta.Test
  ( testSuite
  ) where

import Control.Arrow              (second)
import Data.Char                  (isSpace)
import Data.Either.Custom
import File.Format.Fasta.Internal
import File.Format.Fasta.Parser
import Safe                       (headMay)
import Test.Tasty                 (TestTree,testGroup)
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Text.Parsec                (parse,eof)

testSuite :: TestTree
testSuite = testGroup "Fasta Format"
  [ testGroup "Fasta Generalized Combinators" [identifier',commentBody',identifierLine']
  , testGroup "Fasta Parser" [fastaSequence',fastaTaxonSequenceDefinition',fastaStreamParser']
  ]

identifier' :: TestTree
identifier' = testGroup "identifier" $ [invariant, valid, invalid]
  where
    valid         = testGroup "Valid taxon labels"   $ success <$>   validTaxonLabels
    invalid       = testGroup "Invalid taxon labels" $ failure <$> invalidTaxonLabels
    success str   = testCase (show str) . assert $ parse' str == Right str
    failure str   = testCase (show str) . assert . isLeft $ parse' str
    parse' = parse (identifier <* eof) ""
    invalidTaxonLabels =
      [ x ++ [s] ++ y |  e    <- validTaxonLabels
                      ,  s    <- "$ \t\r\n"
                      ,  i    <- [length e `div` 2]
                      , (x,y) <- [i `splitAt` e] 
      ]
    invariant = testProperty "fastaLabel invariant" f
      where 
        f x = null str || parse identifier "" str == Right res
          where
            str = takeWhile validIdentifierChar x
            res = headOrEmpty $ words str

validTaxonLabels :: [String]
validTaxonLabels = 
  [ "Peripatidae"
  , "Colossendeis"
  , "Ammotheidae"
  , "Buthidae"
  , "Mygalomorphae"
  ]

commentBody' :: TestTree
commentBody' = testGroup "commentBody" [generalComment, prependedDollarSign, validComments]
  where
    generalComment :: TestTree
    generalComment = testProperty "General comment structure" f
      where
        f x = hasLeadingDollarSign 
           || null res
           || parse commentBody "" x == Right res
          where
            res = unwords . words $ takeWhile (not.(`elem`"\n\r")) x
            hasLeadingDollarSign = let y = dropWhile isSpace x
                                   in  headMay y == Just '$'
    prependedDollarSign :: TestTree
    prependedDollarSign = testProperty "Comments defined with leading dollar sign" $ prepended '$'
      where
        prepended :: Char -> String -> Bool
        prepended c x = null x || null line'
                     || ( parse commentBody "" (            c   : line) == Right line'
                       && parse commentBody "" (      ' ' : c   : line) == Right line'
                       && parse commentBody "" (      c   : ' ' : line) == Right line'
                       && parse commentBody "" (' ' : c   : ' ' : line) == Right line'
                        )
          where
            line  = takeWhile (not . (`elem`"\n\r")) x
            line' = unwords $ words line
    validComments = testGroup "Valid comments" $ success <$> validCommentBodies
      where 
        success str = testCase (show str) . assert $ parse' str == Right "A species of animal"
        parse' = parse (commentBody <* eof) ""

validCommentBodies :: [String]
validCommentBodies =
  [ "$A species of animal"
  , " $A species of animal"
  , "$ A species of animal"
  , " $ A species of animal"
  , " A species of animal"
  ]

identifierLine' :: TestTree
identifierLine' = testGroup "fastaLabelLine" $ [validWithoutComments, validWithComments]
  where
    parse'               = parse (identifierLine <* eof) ""
    success (res,str)    = testCase (show str) . assert $ parse' str == Right res
    validWithoutComments = testGroup "Valid taxon label lines without comemnts" $ success <$> validTaxonCommentlessLines
    validWithComments    = testGroup "Valid taxon label lines with comments"    $ success <$> validTaxonCommentLines

validTaxonCommentLines     :: [(String, String)]
validTaxonCommentLines     = zip validTaxonLabels validTaxonCommentedLabels 
validTaxonCommentlessLines :: [(String, String)]
validTaxonCommentlessLines = zip  validTaxonLabels (inlineLabel <$> validTaxonLabels)
validTaxonCommentedLabels  :: [String]
validTaxonCommentedLabels  = inlineLabel <$> zipWith (++) validTaxonLabels validCommentBodies
inlineLabel :: String -> String
inlineLabel x = concat ["> ", x, "\n"]

fastaSequence' :: TestTree
fastaSequence' = testGroup "fastaNucleotides" $ [valid]
  where
    parse' = parse fastaSequence ""
    success (res,str) = testCase (show str) . assert $ parse' str == Right res
    valid = testGroup "Valid sequences" $ success <$> validSequences

validSequences :: [(String,String)]
validSequences =
      [ ("-GATACA-", "-GATACA-\n"         )
      , ("-GATACA-", "- G ATA CA- \n"     )
      , ("-GATACA-", "-GAT\nACA-\n"       )
      , ("-GATACA-", " -G A\nT\n AC A- \n")
      , ("-GATACA-", "-GA\n\nT\n \nACA-\n")
      ]

fastaTaxonSequenceDefinition' :: TestTree
fastaTaxonSequenceDefinition' = testGroup "fastaTaxonSequenceDefinition" $ [valid]
  where
    parse'              = parse fastaTaxonSequenceDefinition ""
    success (res,str)   = testCase (show str) . assert $ parse' str == Right res
    valid               = testGroup "Valid sequences" $ success <$> validTaxonSequences

validTaxonLines     :: [(String,String)]
validTaxonLines     = validTaxonCommentLines ++ validTaxonCommentlessLines
validTaxonSequences :: [(FastaSequence,String)]
validTaxonSequences = zipWith f validTaxonLines validSequences
  where
    f (x,str) (y,seq')  = (FastaSequence x y, concat [str,"\n",seq'])

fastaStreamParser' :: TestTree
fastaStreamParser' = testGroup "fastaStreamParser" $ [testGroup "Valid stream" $ [validStream]]
  where
    parse'      = parse fastaStreamParser ""
    validStream = testCase "Concatenateed fasta stream" . assert $ parse' str == Right res
    (res,str)   = second concat $ unzip validTaxonSequences

headOrEmpty :: [[a]] -> [a]
headOrEmpty = maybe [] id . headMay

