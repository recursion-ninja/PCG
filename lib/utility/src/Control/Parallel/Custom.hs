------------------------------------------------------------------------------
-- |
-- Module      :  Control.Parallel.Custom
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Control.Parallel.Custom
  ( parmap
  , parZipWith
  , parZipWith3
  ) where


import Control.Parallel.Strategies
import Data.Key
import Prelude                     hiding (zipWith)


-- |
-- Map a function over a traversable structure in parrallel.
-- Should be prefered over 'parMap' which is fixed to lists.
parmap :: Traversable t => Strategy b -> (a -> b) -> t a -> t b
parmap strat f = withStrategy (parTraversable strat) . fmap f


-- |
-- Zip two traversable, zippable structures in parrallel with a function.
parZipWith :: (Traversable t , Zip t) => Strategy c -> (a -> b -> c) -> t a -> t b -> t c
parZipWith strat f lhs rhs = withStrategy (parTraversable strat) $ zipWith f lhs rhs


-- |
-- Zip three traversable, zippable structures in parrallel with a function.
parZipWith3 :: (Traversable t, Zip t) => Strategy d -> (a -> b -> c -> d) -> t a -> t b -> t c -> t d
parZipWith3 strat f x y z = withStrategy (parTraversable strat) $ zap (zipWith f x y) z
