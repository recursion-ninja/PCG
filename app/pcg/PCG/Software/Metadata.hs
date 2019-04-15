{-# LANGUAGE TemplateHaskell #-}

module PCG.Software.Metadata
  ( softwareName
  , shortVersionInformation
  , fullVersionInformation
  ) where

import Data.Foldable
import Data.Semigroup                     ((<>))
import Data.Version                       (showVersion)
import Development.GitRev                 (gitCommitCount, gitHash)
import Paths_phylogenetic_component_graph (version)


-- |
-- Name of the software package.
softwareName :: String
softwareName = "Phylogenetic Component Graph"


-- |
-- Brief description of the software version.
shortVersionInformation :: String
shortVersionInformation = "(alpha) version " <> showVersion version


-- |
-- Full escription of the software version.
--
-- Uses @TemplateHaskell@ to splice in git hash and commit count information
-- from the compilation environment.
fullVersionInformation :: String
fullVersionInformation = fold
    [ softwareName
    , " "
    , shortVersionInformation
    , " ["
    , take 7 $(gitHash)
    , "] ("
    , $(gitCommitCount)
    , " commits)"
    ]