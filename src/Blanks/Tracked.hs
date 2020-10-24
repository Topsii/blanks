{-# LANGUAGE DeriveAnyClass #-}

-- | Utilities for gathering and caching sets of free variables.
module Blanks.Tracked
  ( Tracked (..)
  , mkTrackedFree
  , mkTrackedBound
  , shiftTracked
  , WithTracked (..)
  , forgetTrackedScope
  , trackScope
  , trackScopeSimple
  ) where

import Blanks.Conversion (scopeAnno)
import Blanks.LocScope (LocScope, pattern LocScopeBinder, pattern LocScopeBound, pattern LocScopeEmbed,
                        pattern LocScopeFree, locScopeHoistAnno)
import Blanks.Scope (Scope)
import Control.DeepSeq (NFData)
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Generics (Generic)

data Tracked a = Tracked
  { trackedFree :: !(Set a)
  , trackedBound :: !(Set Int)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

mkTrackedFree :: a -> Tracked a
mkTrackedFree a = Tracked (Set.singleton a) Set.empty

mkTrackedBound :: Int -> Tracked a
mkTrackedBound b = Tracked Set.empty (Set.singleton b)

shiftTracked :: Int -> Tracked a -> Tracked a
shiftTracked i t@(Tracked f b) =
  if Set.null b
    then t
    else
      let !b' = if Set.findMax b < i then Set.empty else Set.dropWhileAntitone (< 0) (Set.mapMonotonic (\x -> x - i) b)
      in Tracked f b'

instance Ord a => Semigroup (Tracked a) where
  Tracked f1 b1 <> Tracked f2 b2 = Tracked (Set.union f1 f2) (Set.union b1 b2)

instance Ord a => Monoid (Tracked a) where
  mempty = Tracked Set.empty Set.empty
  mappend = (<>)

data WithTracked a l = WithTracked
  { withTrackedState :: !(Tracked a)
  , withTrackedEnv :: !l
  } deriving stock (Eq, Show, Generic, Functor, Foldable, Traversable)
    deriving anyclass (NFData)

forgetTrackedScope :: Functor f => LocScope (WithTracked a l) n f z -> LocScope l n f z
forgetTrackedScope = locScopeHoistAnno withTrackedEnv

trackScopeInner :: (Traversable f, Ord a) => LocScope l n f a -> (Tracked a, LocScope (WithTracked a l) n f a)
trackScopeInner s =
  case s of
    LocScopeBound l b ->
      let !t = Tracked Set.empty (Set.singleton b)
          !m = WithTracked t l
      in (t, LocScopeBound m b)
    LocScopeFree l a ->
      let !t = Tracked (Set.singleton a) Set.empty
          !m = WithTracked t l
      in (t, LocScopeFree m a)
    LocScopeBinder l n i e ->
      let !(t0, y) = trackScopeInner e
          !t = shiftTracked n t0
          !m = WithTracked t l
      in (t, LocScopeBinder m n i y)
    LocScopeEmbed l fe ->
      let (!t, !fy) = traverse trackScopeInner fe
          !m = WithTracked t l
      in (t, LocScopeEmbed m fy)

trackScope :: (Traversable f, Ord a) => LocScope l n f a -> LocScope (WithTracked a l) n f a
trackScope = snd . trackScopeInner

trackScopeSimple :: (Traversable f, Ord a) => Scope n f a -> LocScope (Tracked a) n f a
trackScopeSimple = locScopeHoistAnno withTrackedState . trackScope . scopeAnno ()
