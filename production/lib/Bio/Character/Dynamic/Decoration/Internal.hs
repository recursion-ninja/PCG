-----------------------------------------------------------------------------
-- |
-- Module      :  Bio.Character.Dynamic.Decoration.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------

{-# LANGUAGE FlexibleInstances, FunctionalDependencies, MultiParamTypeClasses #-}

module Bio.Character.Dynamic.Decoration.Internal where

import           Bio.Character.Dynamic.Class
import           Bio.Character.Dynamic.Decoration.Class
import           Control.Lens


{-
class ( HasEncoded s a
      , EncodableDynamicCharacter a
      ) => DynamicDecoration s a | s -> a where


class ( HasFinalGapped         s a
      , HasFinalUngapped       s a
      , HasPreliminaryGapped   s a
      , HasPreliminaryUngapped s a
      , DynamicDecoration      s a
      ) => DirectOptimizationDecoration s a | s -> a where


class ( HasImpliedAlignment           s a
      , DirectOptimizationDecoration  s a
      ) => ImpliedAlignmentDecoration s a | s -> a where
-}


data InitialEncodedDecoration d
   = InitialEncodedDecoration
   { initialEncodedDecorationEncodedField :: d
   }
     

instance HasEncoded (InitialEncodedDecoration d) d where

    encoded = lens initialEncodedDecorationEncodedField (\e x -> e { initialEncodedDecorationEncodedField = x })


instance EncodableDynamicCharacter d => DynamicDecoration (InitialEncodedDecoration d) d where
