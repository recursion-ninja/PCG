{-# LANGUAGE BangPatterns, FlexibleContexts #-}

module PCG.Command.Types.Report.Evaluate
  ( evaluate
  ) where

--import           Analysis.Parsimony.Binary.Optimization
import           Bio.Phylogeny.Solution
--import           Bio.Phylogeny.Tree.Binary
import           Control.Monad.IO.Class
import           Control.Evaluation
import           PCG.Command.Types (Command(..))
import           PCG.Command.Types.Report.TaxonMatrix
--import           PCG.Command.Types.Report.GraphViz
import           PCG.Command.Types.Report.Internal
--import           PCG.Command.Types.Report.Metadata
--import           PCG.Command.Types.Report.Newick

evaluate :: Command -> SearchState -> SearchState
evaluate (REPORT target format) old = do
    stateValue <- old
    case generateOutput stateValue format of
     Left  errMsg -> fail errMsg
     Right output ->
       case target of
         OutputToStdout -> old <> info output
         OutputToFile f -> old <* liftIO (writeFile f output)

evaluate _ _ = fail "Invalid READ command binding"

-- | Function to add optimization to the newick reporting
-- TODO: change this error into a warning
{-
addOptimization :: StandardSolution -> StandardSolution --Graph -> Graph
addOptimization result
  | allBinary = solutionOptimization result
  | otherwise = error ("Cannot perform optimization because graph is not binary, outputting zero cost") result
    where allBinary = all (all verifyBinary) (forests result)
-}

-- TODO: Redo reporting
generateOutput :: StandardSolution -> OutputFormat -> Either String String
generateOutput g (CrossReferences fileNames) = Right $ taxonReferenceOutput g fileNames
--generateOutput g Data            {}          = Right $ newickReport (addOptimization g)
--generateOutput g DotFile         {}          = Right $ dotOutput g
--generateOutput g Metadata        {}          = Right $ metadataCsvOutput g
generateOutput _ _ = Left "Unrecognized 'report' command"
