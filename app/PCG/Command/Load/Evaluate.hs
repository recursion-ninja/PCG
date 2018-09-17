{-# LANGUAGE ScopedTypeVariables #-}
module PCG.Command.Load.Evaluate
  ( evaluate
  )
  where

import           Data.Compact.Serialize                    (unsafeReadCompact)
import           Bio.Graph
import PCG.Command.Save.Evaluate (saveFile)
import Control.Monad.IO.Class (liftIO)


evaluate :: GraphState -> SearchState
evaluate g = do
  (optGraphState :: Either String GraphState) <- liftIO $ unsafeReadCompact saveFile
  case optGraphState of
    Left err         ->  fail $ "Failed to read savefile with error: \n" <> err
    Right graphState ->  pure graphState :: SearchState
