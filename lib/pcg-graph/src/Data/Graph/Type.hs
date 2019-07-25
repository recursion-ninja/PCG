{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE RecordWildCards #-}

module Data.Graph.Type where

import Data.Graph.Indices
import Data.Graph.NodeContext
import Data.Vector (Vector)
-- import qualified Data.Vector as V
import Data.Kind (Type)
import Data.Key
import Data.Vector.Instances ()
import Control.Lens

data GraphShape i n r t
  = GraphShape
  { leafData     :: Vector t
  , internalData :: Vector i
  , networkData  :: Vector n
  , rootData     :: Vector r
  }

data Graph
       (f :: Type -> Type)
       (c :: Type)
       (e :: Type)
       (n :: Type)
       (t :: Type)
  = Graph
  { leafReferences     :: Vector (LeafIndexData     (  t))
  , internalReferences :: Vector (InternalIndexData (f n))
  , networkReferences  :: Vector (NetworkIndexData  (f n))
  , rootReferences     :: Vector (RootIndexData     (f n))
  , cachedData         :: c
  }

instance Functor f => Bifunctor (Graph f c e) where
  bimap f g graph@(Graph{..}) =
    graph
      { leafReferences     = fmap (fmap g) leafReferences
      , internalReferences = fmap (fmap (fmap f)) internalReferences
      , networkReferences  = fmap (fmap (fmap f)) networkReferences
      , rootReferences     = fmap (fmap (fmap f)) rootReferences
      }

class HasLeafReferences s t a b | s -> a, t -> b, s b -> t, t a -> s where
  _leafReferences :: Lens s t a b

instance HasLeafReferences
           (Graph f c e n t)
           (Graph f c e n t')
           (Vector (IndexData LeafContext t))
           (Vector (IndexData LeafContext t')) where
  _leafReferences = lens leafReferences (\g l -> g {leafReferences = l})

class HasInternalReferences s a | s -> a where
  _internalReferences :: Lens' s a

instance HasInternalReferences
           (Graph f c e n t)
           (Vector (IndexData InternalContext (f n))) where
  _internalReferences = lens internalReferences (\g fn -> g {internalReferences = fn})

class HasNetworkReferences s a | s -> a where
  _networkReferences :: Lens' s a

instance HasNetworkReferences
           (Graph f c e n t)
           (Vector (IndexData NetworkContext (f n))) where
  _networkReferences = lens networkReferences (\g fn -> g {networkReferences = fn})

class HasRootReferences s a | s -> a where
  _rootReferences :: Lens' s a

instance HasRootReferences
           (Graph f c e n t)
           (Vector (IndexData RootContext (f n))) where
  _rootReferences = lens rootReferences (\g fn -> g {rootReferences = fn})

class HasCachedData s t a b | s -> a, t -> b, s b -> t, t a -> b where
  _cachedData :: Lens s t a b

instance HasCachedData
           (Graph f c1 e n t)
           (Graph f c2 e n t)
           c1
           c2 where
  _cachedData = lens cachedData (\g c2 -> g {cachedData = c2})



index :: Graph f c e n t -> TaggedIndex -> NodeContext
index graph taggedIndex =
  let
    ind = untagValue taggedIndex
  in
  case getTag taggedIndex of
    LeafTag    ->   leafNodeContext
                  . (^. _nodeContext)
                  . (! ind)
                  .  leafReferences
                  $ graph

    InternalTag ->   internalNodeContext
                   . (^. _nodeContext)
                   . (! ind)
                   .  internalReferences
                   $ graph

    NetworkTag  ->   networkNodeContext
                   .  (^. _nodeContext)
                   . (! ind)
                   .  networkReferences
                   $ graph

    RootTag     ->   rootNodeContext
                   . (^. _nodeContext)
                   . (! ind)
                   .  rootReferences
                   $ graph
