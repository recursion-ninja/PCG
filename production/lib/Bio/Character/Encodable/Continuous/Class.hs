-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Character.Encodable.Continuous.Class
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts, FunctionalDependencies, MultiParamTypeClasses #-}

module Bio.Character.Encodable.Continuous.Class where


-- |
-- A character class for continuous characters.
class Ord c => ContinuousCharacter c where

    toContinuousCharacter :: Real r => Maybe r -> c
