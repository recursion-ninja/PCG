{-# LANGUAGE ScopedTypeVariables #-}
module PCG.Command.Save.Evaluate
  ( evaluate
  ) where

import Bio.Graph
import Control.Evaluation
import Control.Monad.IO.Class         (liftIO)
import Control.Monad.Trans.Validation
import Data.FileSource                (FileSource)
import Data.FileSource.IO
import Data.Functor                   (($>))
import Data.Validation
import PCG.Command.Save


evaluate :: SaveCommand -> GraphState -> SearchState
evaluate (SaveCommand fileSource serial) g =
    case serial of
      Binary  -> writeOutBinaryEncoding fileSource g $> g


writeOutBinaryEncoding :: FileSource -> GraphState -> EvaluationT GlobalSettings IO ()
writeOutBinaryEncoding path g = do
    result <- liftIO . runValidationT $ serializeBinary path g
    case result of
      Success _    -> pure ()
      Failure oErr -> failWithPhase Outputting oErr
