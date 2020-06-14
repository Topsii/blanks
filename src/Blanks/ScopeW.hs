{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ViewPatterns #-}

module Blanks.ScopeW
  ( ScopeW (..)
  , ScopeWRawFold
  , ScopeWFold
  , scopeWFree
  , scopeWEmbed
  , scopeWAbstract
  , scopeWUnAbstract
  , scopeWInstantiate
  , scopeWApply
  , scopeWBind
  , scopeWBindOpt
  , scopeWRawFold
  , scopeWFold
  , scopeWLiftAnno
  ) where

import Blanks.NatNewtype (NatNewtype, natNewtypeTo, natNewtypeFrom)
import Blanks.Sub (SubError (..))
import Blanks.UnderScope (UnderScope, UnderScopeFold, pattern UnderScopeBinder, pattern UnderScopeBound, pattern UnderScopeEmbed,
                          pattern UnderScopeFree, underScopeFold, underScopeShift)
import Data.Bifoldable (bifoldr)
import Data.Bifunctor (bimap)
import Data.Bitraversable (bitraverse)
import Data.Functor.Adjunction (Adjunction (..))
import Data.Maybe (fromMaybe)
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq

-- * ScopeW, patterns, and instances

newtype ScopeW t n f g a = ScopeW
  { unScopeW :: t (UnderScope n f (g a) a)
  }

instance Eq (t (UnderScope n f (g a) a)) => Eq (ScopeW t n f g a) where
  ScopeW tu == ScopeW tv = tu == tv

instance Show (t (UnderScope n f (g a) a)) => Show (ScopeW t n f g a) where
  showsPrec d (ScopeW tu) = showString "ScopeW " . showsPrec (d+1) tu

instance (Functor t, Functor f, Functor g) => Functor (ScopeW t n f g) where
  fmap f (ScopeW tu) = ScopeW (fmap (bimap (fmap f) f) tu)

instance (Foldable t, Foldable f, Foldable g) => Foldable (ScopeW t n f g) where
  foldr f z (ScopeW tu) = foldr (flip (bifoldr (flip (foldr f)) f)) z tu

instance (Traversable t, Traversable f, Traversable g) => Traversable (ScopeW t n f g) where
  traverse f (ScopeW tu) = fmap ScopeW (traverse (bitraverse (traverse f) f) tu)

type ScopeC t u n f g = (Adjunction t u, Applicative u, Functor f, NatNewtype (ScopeW t n f g) g)

-- * Smart constructors, shift, and bind

scopeWMod :: ScopeC t u n f g => (UnderScope n f (g a) a -> u x) -> g a -> x
scopeWMod f = rightAdjunct f . unScopeW . natNewtypeFrom

scopeWModOpt :: ScopeC t u n f g => (UnderScope n f (g a) a -> Maybe (u (g a))) -> g a -> g a
scopeWModOpt f s = rightAdjunct (fromMaybe (pure s) . f) (unScopeW (natNewtypeFrom s))

scopeWModM :: (ScopeC t u n f g, Traversable m) => (UnderScope n f (g a) a -> m (u x)) -> g a -> m x
scopeWModM f = rightAdjunct (sequenceA . f) . unScopeW . natNewtypeFrom

scopeWBound :: ScopeC t u n f g => Int -> u (g a)
scopeWBound b = fmap (natNewtypeTo . ScopeW) (unit (UnderScopeBound b))

scopeWFree :: ScopeC t u n f g => a -> u (g a)
scopeWFree a = fmap (natNewtypeTo . ScopeW) (unit (UnderScopeFree a))

scopeWShift :: ScopeC t u n f g => Int -> g a -> g a
scopeWShift = scopeWShiftN 0

scopeWShiftN :: ScopeC t u n f g => Int -> Int -> g a -> g a
scopeWShiftN c d (natNewtypeFrom -> ScopeW tu) = natNewtypeTo (ScopeW (fmap (underScopeShift scopeWShiftN c d) tu))

scopeWBinder :: ScopeC t u n f g => Int -> n -> g a -> u (g a)
scopeWBinder r n e = fmap (natNewtypeTo . ScopeW) (unit (UnderScopeBinder r n e))

scopeWEmbed :: ScopeC t u n f g => f (g a) -> u (g a)
scopeWEmbed fe = fmap (natNewtypeTo . ScopeW) (unit (UnderScopeEmbed fe))

scopeWBind :: ScopeC t u n f g => (a -> u (g b)) -> g a -> g b
scopeWBind f = scopeWBindN f 0

scopeWBindN :: ScopeC t u n f g => (a -> u (g b)) -> Int -> g a -> g b
scopeWBindN f = scopeWMod . go where
  go i us =
    case us of
      UnderScopeBound b -> scopeWBound b
      UnderScopeFree a -> fmap (scopeWShift i) (f a)
      UnderScopeBinder r x e -> scopeWBinder r x (scopeWBindN f (i + r) e)
      UnderScopeEmbed fe -> scopeWEmbed (fmap (scopeWBindN f i) fe)

scopeWBindOpt :: ScopeC t u n f g => (a -> Maybe (u (g a))) -> g a -> g a
scopeWBindOpt f = scopeWBindOptN f 0

scopeWBindOptN :: ScopeC t u n f g => (a -> Maybe (u (g a))) -> Int -> g a -> g a
scopeWBindOptN f = scopeWModOpt . go where
  go i us =
    case us of
      UnderScopeBound _ -> Nothing
      UnderScopeFree a -> fmap (fmap (scopeWShift i)) (f a)
      UnderScopeBinder r x e -> Just (scopeWBinder r x (scopeWBindOptN f (i + r) e))
      UnderScopeEmbed fe -> Just (scopeWEmbed (fmap (scopeWBindOptN f i) fe))

-- -- * Abstraction

subScopeWAbstract :: (ScopeC t u n f g, Eq a) => Int -> n -> Seq a -> g a -> u (g a)
subScopeWAbstract r n ks e =
  let f = fmap scopeWBound . flip Seq.elemIndexL ks
      e' = scopeWBindOpt f e
  in scopeWBinder r n e'

scopeWAbstract :: (ScopeC t u n f g, Eq a) => n -> Seq a -> g a -> u (g a)
scopeWAbstract n ks =
  let r = Seq.length ks
  in subScopeWAbstract r n ks . scopeWShift r

scopeWUnAbstract :: ScopeC t u n f g => Seq a -> g a -> g a
scopeWUnAbstract ks = scopeWInstantiate (fmap scopeWFree ks)

scopeWInstantiate :: ScopeC t u n f g => Seq (u (g a)) -> g a -> g a
scopeWInstantiate = scopeWInstantiateN 0

scopeWInstantiateN :: ScopeC t u n f g => Int -> Seq (u (g a)) -> g a -> g a
scopeWInstantiateN h vs = scopeWModOpt (go h) where
  go i us =
    case us of
      UnderScopeBound b -> vs Seq.!? (b - i)
      UnderScopeFree _ -> Nothing
      UnderScopeBinder r n e ->
        let vs' = fmap (fmap (scopeWShift r)) vs
            e' = scopeWInstantiateN (r + i) vs' e
        in Just (scopeWBinder r n e')
      UnderScopeEmbed fe -> Just (scopeWEmbed (fmap (scopeWInstantiateN i vs) fe))

scopeWApply :: ScopeC t u n f g => Seq (u (g a)) -> g a -> Either SubError (g a)
scopeWApply vs = scopeWModM go where
  go us =
    case us of
      UnderScopeBinder r _ e ->
        let len = Seq.length vs
        in if len == r
              then Right (pure (scopeWShift (-1) (scopeWInstantiate vs e)))
              else Left (ApplyError len r)
      _ -> Left NonBinderError

-- * Folds

type ScopeWRawFold n f g a r = UnderScopeFold n f (g a) a r
type ScopeWFold u n f g a r = ScopeWRawFold n f g a (u r)

scopeWRawFold :: (NatNewtype (ScopeW t n f g) g, Functor t) => ScopeWRawFold n f g a r -> g a -> t r
scopeWRawFold usf = fmap (underScopeFold usf) . unScopeW . natNewtypeFrom

scopeWFold :: (NatNewtype (ScopeW t n f g) g, Adjunction t u) => ScopeWFold u n f g a r -> g a -> r
scopeWFold usf = counit . scopeWRawFold usf

-- * Annotation functions

scopeWLiftAnno :: (NatNewtype (ScopeW t n f g) g, Functor t) => t a -> g a
scopeWLiftAnno = natNewtypeTo . ScopeW . fmap UnderScopeFree
