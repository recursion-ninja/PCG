module Bio.Graph.BinaryRenderingTree where


import Control.Arrow             ((&&&), (***))
import Data.Foldable
import Data.List.NonEmpty hiding (length)
import Data.Semigroup
import Prelude            hiding (head, splitAt)

data  BinaryRenderingTree
    = Leaf String
    | Node Word Word (Maybe String) (NonEmpty BinaryRenderingTree)
    deriving (Eq)


subtreeSize :: BinaryRenderingTree -> Word
subtreeSize (Leaf x)       = 1
subtreeSize (Node _ x _ _) = x


subtreeDepth :: BinaryRenderingTree -> Word
subtreeDepth (Leaf x)     = 0
subtreeDepth (Node x _ _ _) = x


horizontalRendering :: BinaryRenderingTree -> String
horizontalRendering = fold . intersperse "\n" . go
  where
    go :: BinaryRenderingTree -> NonEmpty String
    go (Leaf label) = pure $ "─ " <> label
    go (Node _ _ labelMay kids) = sconcat paddedSubtrees
      where
        paddedSubtrees   = maybe prefixedSubtrees (`applyPadding` prefixedSubtrees) labelMay
        
        prefixedSubtrees  :: NonEmpty (NonEmpty String)
        prefixedSubtrees = applyPrefixes alignedSubtrees

        alignedSubtrees  :: NonEmpty (NonEmpty String)
        alignedSubtrees  = applySubtreeAlignment maxSubtreeDepth <$> renderedSubtrees

        renderedSubtrees :: NonEmpty (Int, NonEmpty String)
        renderedSubtrees = fmap (length . head &&& id) $ go <$> sortWith subtreeSize kids

        maxSubtreeDepth  = maximum $ fst <$> renderedSubtrees

    applyPadding :: String -> NonEmpty (NonEmpty String) -> NonEmpty (NonEmpty String)
    applyPadding e input =
        case input of
          v:|[]     -> applyAtCenter e pad pad v :| []
          v:|(x:xs) -> fmap (pad<>) v :| (applyAtCenter e pad pad x : fmap (fmap (pad<>)) xs)
      where
        pad   = replicate (length e) ' '

    applyPrefixes :: NonEmpty (NonEmpty String) -> NonEmpty (NonEmpty String)
    applyPrefixes = go True
      where
        go :: Bool -> NonEmpty (NonEmpty String) -> NonEmpty (NonEmpty String) 
        go True  (v:|[])     = pure $ applyAtCenter "─" " " " " v
        go False (v:|[])     = pure $ applyAtCenter "└" "│" " " v
        go True  (v:|(x:xs)) = applyPrefixAndGlue  v "┤" "┌" " " "│" (x:|xs)
        go False (v:|(x:xs)) = applyPrefixAndGlue  v "│" "├" "│" " " (x:|xs)

        applyPrefixAndGlue v glue center upper lower xs = pure (applyAtCenter center upper lower v)
                                          <> pure (pure glue)
                                          <> go False xs

    applySubtreeAlignment :: Int -> (Int, NonEmpty String) -> NonEmpty String
    applySubtreeAlignment maxLength (currLength, xs) = applyAtCenter branch pad pad xs
      where
        branch = replicate (maxLength - currLength) '─'
        pad    = replicate (maxLength - currLength) ' '

    applyAtCenter :: String -> String -> String -> NonEmpty String -> NonEmpty String
    applyAtCenter center     _     _ (x:|[]) = (center<>x) :| []
    applyAtCenter center upper lower (x:|xs) = ( upper<>x) :| snd (foldr f (False, []) xs)
      where
        f :: String -> (Bool, [String]) -> (Bool, [String])
        f e@(h:_) (crossedMidPoint, acc)
          | crossedMidPoint || h `notElem` "└┌│ " = ( True, (center<>e):acc)
          | crossedMidPoint                      = ( True, ( upper<>e):acc)
          | otherwise                            = (False, ( lower<>e):acc)
