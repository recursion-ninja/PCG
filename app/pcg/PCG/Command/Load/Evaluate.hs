{-# LANGUAGE ScopedTypeVariables #-}
module PCG.Command.Load.Evaluate
  ( evaluate
  ) where

import Bio.Graph
import Control.Evaluation
import Control.Monad.IO.Class         (liftIO)
import Control.Monad.Trans.Validation
import Data.FileSource.IO
import Data.Validation
import PCG.Command.Load


evaluate :: LoadCommand -> SearchState
evaluate (LoadCommand filePath) = do
    result <- liftIO . runValidationT $ deserializeBinary filePath
    case result of
      Success gVal -> pure gVal :: SearchState
      Failure eVal ->
        case eVal of
          Left  iErr-> failWithPhase Inputing iErr
          Right pErr-> failWithPhase  Parsing pErr
