{-# LANGUAGE BangPatterns, FlexibleContexts #-}

module PCG.Command.Types.Report.Evaluate
  ( evaluate
  ) where

import           Analysis.Parsimony.Binary.Optimization
import           Bio.Phylogeny.Graph
import           Bio.Phylogeny.Tree.Binary
import           Control.Monad.IO.Class
import           Control.Evaluation
import           PCG.Command.Types (Command(..))
import           PCG.Command.Types.Report.TaxonMatrix
import           PCG.Command.Types.Report.GraphViz
import           PCG.Command.Types.Report.Internal
import           PCG.Command.Types.Report.Metadata
import           PCG.Command.Types.Report.Newick

import Debug.Trace

evaluate :: Command -> SearchState -> SearchState
{--}
--evaluate _ old | trace ("evaluate search state for output " ++ show old) False = undefined
evaluate (REPORT target format) old = do
    stateValue <- old
    case generateOutput stateValue format of
     Left  errMsg -> fail errMsg
     Right output ->
       case target of
         OutputToStdout -> old <> info output
         OutputToFile f -> old <* liftIO (writeFile f output)

evaluate _ _ = fail "Invalid READ command binding"
{--}

-- | Function to add optimization to the newick reporting
-- TODO: change this trace into a warning
addOptimization :: Graph -> Graph
addOptimization g@(Graph inDags) 
  | allBinary = graphOptimization 1 g
  | otherwise = trace ("Cannot perform optimization because graph is not binary, outputting zero cost") g
    where allBinary = foldr (\d acc -> acc && verifyBinary d) True inDags

generateOutput :: Graph -> OutputFormat -> Either String String
-- Don't ignore names later
generateOutput g (CrossReferences filterFiles)  = Right $ taxonReferenceOutput g filterFiles
generateOutput g Data            {}             = Right $ newickReport (addOptimization g)
generateOutput g DotFile         {}             = Right $ dotOutput g
generateOutput g Metadata        {}             = Right $ metadataCsvOutput g
generateOutput _ _ = Left "Unrecognized 'report' command"
