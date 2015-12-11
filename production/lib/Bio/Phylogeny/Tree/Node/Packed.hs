{-# LANGUAGE FunctionalDependencies #-}

module Bio.Phylogeny.Tree.Node.Packed where

import Bio.Sequence.Packed

-- | A packed node has its packed data
class PackedNode a b | a -> b where
    packed :: a -> PackedSeq b
    setPacked :: a -> PackedSeq b -> a