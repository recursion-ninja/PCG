-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Evaluation.Internal
-- Copyright   :  (c) 2015-2015 Ward Wheeler
-- License     :  BSD-style
--
-- Maintainer  :  wheeler@amnh.org
-- Stability   :  provisional
-- Portability :  portable
--
-- The 'Evaluation' monad definition.
-----------------------------------------------------------------------------

{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Control.Evaluation.Internal
  ( ErrorPhase(..)
  , Evaluation(..)
  , Notification(..)
  , failWithPhase
  , notifications
  , prependNotifications
  ) where

import           Control.Applicative
import           Control.DeepSeq
import           Control.Evaluation.Unit
import           Control.Monad.Fail          (MonadFail)
import qualified Control.Monad.Fail          as F
import           Control.Monad.Fix           (MonadFix (..))
import           Control.Monad.Logger
import           Control.Monad.Writer.Strict (MonadWriter (..))
import           Control.Monad.Zip           (MonadZip (..))
import           Data.Data
import           Data.DList                  (DList)
import           Data.Foldable
import           Data.Functor.Alt            (Alt (..))
import           Data.Functor.Apply          (Apply (..))
import           Data.Functor.Bind           (Bind (..))
import           Data.Functor.Classes        (Eq1 (..), Ord1 (..), Show1 (..))
import           Data.String
import           Data.Text                   (Text)
import           GHC.Exts                    (IsList (fromList))
import           GHC.Generics                hiding (Prefix)
import           Test.QuickCheck
import           Test.QuickCheck.Instances   ()
import           TextShow                    (TextShow)


-- |
-- Represents the types of contextual notifications that can be generated by
-- the evaluation.
data  Notification
    = Warning     Text
    | Information Text
    deriving (Eq, Data, Generic, NFData, Ord, Show)


-- |
-- Represents monoidal evaluations of a value 'a' with contextual notifications.
-- Stores a list of ordered contextual notifications retrievable by
-- 'notifications'. Holds the evaluation state 'a' retrievable 'evaluationResult'.
data  Evaluation a
    = Evaluation (DList Notification) (EvalUnit a)
    deriving (Eq, Generic, NFData)


instance Alt Evaluation where

    {-# INLINEABLE (<!>) #-}

    (<!>) lhs@(Evaluation _ x) rhs@(Evaluation _ y) =
        case runEvalUnit x of
          Right _ -> lhs
          _       ->
              case runEvalUnit y of
                Right _ -> rhs
                _       -> lhs


instance Applicative Evaluation where

    {-# INLINEABLE (<*>)  #-}
    {-# INLINE     (*>)   #-}
    {-# INLINE     (<*)   #-}
    {-# INLINE     pure   #-}
    {-# INLINE     liftA2 #-}

    pure = Evaluation mempty . pure

    (<*>) = (<.>)

    (*>)  = (.>)

    (<*)  = (<.)

    liftA2 = liftF2


instance Apply Evaluation where

    {-# INLINEABLE (<.>)  #-}
    {-# INLINE     (.>)   #-}
    {-# INLINE     (<.)   #-}
    {-# INLINE     liftF2 #-}

    (<.>) = apply (<.>)

    (.>)  = apply (.>)

    (<.)  = apply (<.)

    liftF2 op (Evaluation ms x) (Evaluation ns y) =
        case runEvalUnit x of
          Left  s -> Evaluation ms . EU $ Left s
          Right a -> Evaluation (ms <> ns) $
              case runEvalUnit y of
                Left  s -> EU $ Left s
                Right b -> pure $ a `op` b


instance Arbitrary a => Arbitrary (Evaluation a) where

    {-# INLINE arbitrary #-}

    arbitrary = liftArbitrary arbitrary


instance Arbitrary Notification where

    {-# INLINE arbitrary #-}

    arbitrary = oneof [ Information <$> arbitrary, Warning <$> arbitrary ]


instance Arbitrary1 Evaluation where

    {-# INLINE liftArbitrary #-}

    liftArbitrary g = do
        xs <- fromList <$> arbitrary
        n  <- choose (0, 9) :: Gen Word -- 1/10 chance of 'error' value
        case n of
          0 -> pure . Evaluation xs $ fail "Error Description"
          _ -> Evaluation xs . pure <$> g


instance Bind Evaluation where

    {-# INLINEABLE (>>-) #-}
    {-# INLINE     join  #-}

    (>>-) (Evaluation ms x) f =
        case runEvalUnit x of
          Left  s -> Evaluation ms . EU $ Left s
          Right a -> f a `prependNotifications` ms

    join (Evaluation ms x) =
        case runEvalUnit x of
          Left  s                 -> Evaluation ms . EU $ Left s
          Right (Evaluation ns e) -> Evaluation (ms <> ns) e


instance CoArbitrary a => CoArbitrary (Evaluation a) where

    {-# INLINE coarbitrary #-}

    coarbitrary (Evaluation ms e) = coarbitrary (toList ms) . coarbitrary e


instance CoArbitrary Notification where

    {-# INLINE coarbitrary #-}

    coarbitrary = genericCoarbitrary


instance Eq1 Evaluation where

    {-# INLINE liftEq #-}

    liftEq f (Evaluation ms x) (Evaluation ns y) = liftEq f x y && ms == ns


instance Functor Evaluation where

    {-# INLINEABLE fmap #-}

    fmap f (Evaluation ms x) = Evaluation ms (f <$> x)


instance Foldable Evaluation where

    fold        = fold . getEvalUnit

    foldMap f   = foldMap f . getEvalUnit

    foldr   f z = foldr f z . getEvalUnit

    foldl   f z = foldl f z . getEvalUnit

    foldl'  f z = foldl' f z . getEvalUnit

    foldr1  f   = foldr1 f . getEvalUnit

    foldl1  f   = foldl1 f . getEvalUnit

    toList      = toList . getEvalUnit

    null        = null . getEvalUnit

    length      = length . getEvalUnit

    elem e      = elem e . getEvalUnit

    maximum     = maximum . getEvalUnit

    minimum     = minimum . getEvalUnit

    sum         = foldl' (+) 0 . getEvalUnit

    product     = product . getEvalUnit


instance Logger Evaluation a where

    {-# INLINE (<?>) #-}
    {-# INLINE (<@>) #-}

    (<?>) e@(Evaluation ms x) =
        \case
           []   -> e
           y:ys ->
             case runEvalUnit x of
               Left  _ -> e
               _       -> let note = fromString $ y:ys
                          in  Evaluation (ms <> pure (Information note)) x

    (<@>) e@(Evaluation ms x) =
        \case
           []   -> e
           y:ys ->
             case runEvalUnit x of
               Left _ -> e
               _      -> let note = fromString $ y:ys
                         in  Evaluation (ms <> pure (Warning note)) x


instance Monad Evaluation where

    {-# INLINEABLE (>>=)  #-}
    {-# INLINE     (>>)   #-}
    {-# INLINE     return #-}
    {-# INLINE     fail   #-}

    (>>=)  = (>>-)

    (>>)   = (*>)

    return = pure

    fail   = F.fail


instance MonadFail Evaluation where

    {-# INLINE fail #-}

    fail = Evaluation mempty . fail


instance MonadFix Evaluation where

    mfix f = let a = a >>= f in a


instance MonadZip Evaluation where

    {-# INLINEABLE mzip     #-}
    {-# INLINEABLE munzip   #-}
    {-# INLINE     mzipWith #-}

    mzip     = liftF2 (,)

    mzipWith = liftF2

    munzip (Evaluation ms x) =
      case runEvalUnit x of
        Left  s      -> let f = Evaluation ms . EU . Left in  (f s, f s)
        Right (a, b) -> let f = Evaluation ms . pure      in  (f a, f b)


instance MonadWriter (DList Notification) Evaluation where

    writer (a, w) = Evaluation w (pure a)

    listen (Evaluation w a) = Evaluation w ((\x -> (x, w)) <$> a)

    pass (Evaluation w x) =
        case runEvalUnit x of
          Left  s      -> Evaluation    w  . EU $ Left s
          Right (a, f) -> Evaluation (f w) $ pure a


instance Ord a => Ord (Evaluation a) where

    {-# INLINE compare #-}

    compare = liftCompare compare


instance Ord1 Evaluation where

    {-# INLINE liftCompare #-}

    liftCompare cmp (Evaluation ms x) (Evaluation ns y) =
       case liftCompare cmp x y of
         EQ -> ms `compare ` ns
         v  -> v


instance Semigroup (Evaluation a) where

    {-# INLINE (<>) #-}

    (Evaluation ms x) <> (Evaluation ns y) = Evaluation (ms <> ns) (x <> y)


instance Show a => Show (Evaluation a) where

    show = ($ []) . liftShowsPrec showsPrec showList 0


instance Show1 Evaluation where

    liftShowsPrec f g i (Evaluation ms x) = prefix . liftShowsPrec f g i x
      where
        prefix v = unwords
          [ "Evaluation"
          , "[" <> show (length  $ toList ms) <> "]"
          , show $ toList ms
          , v
          ]


instance Traversable Evaluation where

    traverse f (Evaluation ms x) = Evaluation ms <$> traverse f x


-- |
-- Fail and indicate the phase in which the failure occured.
failWithPhase :: TextShow s => ErrorPhase -> s -> Evaluation a
failWithPhase p = Evaluation mempty . evalUnitWithPhase p


-- |
-- Retrieve the ordered list of contextual 'Notification's from the 'Evaluation'.
notifications :: Evaluation a -> [Notification]
notifications (Evaluation ms _) = toList ms


-- |
-- Prepends a 'DList' of 'Notification's to the evaluation. Should only be used
-- internally.
prependNotifications :: Evaluation a -> DList Notification -> Evaluation a
prependNotifications (Evaluation ms x) ns = Evaluation (ns <> ms) x


-- |
-- Retrieve the result state from the 'Evaluation'.
getEvalUnit :: Evaluation a -> EvalUnit a
getEvalUnit (Evaluation _ x) = x


{-# INLINE apply #-}
apply
  :: (EvalUnit a -> EvalUnit b -> EvalUnit c)
  -> Evaluation a -> Evaluation b -> Evaluation c
apply op (Evaluation ms x) (Evaluation ns y) =
    case runEvalUnit x of
      Left  s -> Evaluation ms . EU $ Left s
      _       -> Evaluation (ms <> ns) $ x `op` y
