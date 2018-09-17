-----------------------------------------------------------------------------
-- |
-- Module      :  PCG.Command.Save
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Provides the types for the Save command along with a semantic definition
-- to be consumed by the stream parser.
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE UnboxedSums      #-}

module PCG.Command.Save
  ( SaveCommand (..)
  , saveCommandSpecification
  ) where

import PCG.Syntax.Combinators

data SaveCommand = SaveCommand !FilePath
  deriving Show

saveCommandSpecification :: CommandSpecification SaveCommand
saveCommandSpecification = command "save" . argList $ SaveCommand <$> text
