-----------------------------------------------------------------------------
-- |
-- Module      :  Data.List.Utility
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Functions for finding occurances of elements in a list.
--
----------------------------------------------------------------------------- 

module Data.List.Utility where

import Data.Foldable
import Data.List     (sort,sortBy)
import Data.Map      (assocs,empty,insertWith)
import Data.Ord      (comparing)

isSingleton :: Foldable t => t a -> Bool
isSingleton = f . toList
  where
    f [_] = True
    f  _  = False

-- | Returns the list of elements which are not unique in the input list.
duplicates :: (Foldable t, Ord a) => t a -> [a]
duplicates = duplicates' . sort . toList
  where 
    duplicates' []       = []
    duplicates' [_]      = []
    duplicates' (x:y:ys) = if   x == y
                           then (x:) . duplicates $ dropWhile (==y) ys 
                           else duplicates (y:ys)

-- | Returns the element that occurs the most often in the list.
mostCommon :: Ord a => [a] -> Maybe a
mostCommon [] = Nothing
mostCommon xs = Just . fst . head $ occurances xs


-- | Returns a mapping of each unique element in the list
-- paired with how often the element occurs in the list.
occurances :: Ord a => [a] -> [(a,Int)]
occurances = collateOccuranceMap . buildOccuranceMap
  where
    buildOccuranceMap = foldr occurance empty 
      where
        occurance e = insertWith (const succ) e 1
    collateOccuranceMap = sortBy comparator . assocs
      where
        comparator x y = descending $ comparing snd x y
        descending LT  = GT
        descending GT  = LT
        descending x   = x
