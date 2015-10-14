module TestSuite.GeneratedTests.Internal where

import Control.Arrow    ((&&&))
import Data.Map         (Map,fromList)
import System.Directory

-- | Gets all the given files and thier contents in the specified directory
getFileContentsInDirectory :: FilePath -> IO (Map FilePath String)
getFileContentsInDirectory path = do
    files <- filter isFile <$> getDirectoryContents path
    sequence . fromList $ (id &&& readFile) . withPath <$> files
  where
    isFile = not . all (=='.')
    withPath file = if last path /= '/'
                    then concat [path,"/",file]
                    else concat [path,    file]