-----------------------------------------------------------------------------
-- |
-- Module      :  PCG.Command.Report.Graphviz
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Functionality to output a graphviz format from a Graph
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}

module PCG.Command.Report.GraphViz
  ( generateDotFile
  ) where

import           Bio.Graph
import           Data.GraphViz.Printing
import qualified Data.Text.Lazy         as L


generateDotFile :: GraphState -> L.Text
generateDotFile = (<> "\n") . renderDot . getDotGraph


getDotGraph :: GraphState -> DotCode
getDotGraph = either toDot toDot
