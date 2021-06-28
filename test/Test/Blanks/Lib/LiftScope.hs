module Test.Blanks.Lib.LiftScope where

import Blanks (BinderId, BinderScope, LiftBinder (..), LiftFunctor (..), LiftState, LocScope, State, Tracked,
               WithTracked (..), locScopeAbstract1, locScopeInnerBinder1, locScopeLocation, pattern LocScopeBound,
               pattern LocScopeEmbed, predLiftLocScope, runColocated, scopeAnno, trackScope)
import qualified Data.Sequence as Seq
import Data.Set (Set)
import qualified Data.Set as Set
import Test.Blanks.Lib.SimpleScope (SimpleFunctor (..), SimpleInfo (..), SimpleScope)

type SimpleLiftState = State (LiftState () SimpleInfo SimpleInfo SimpleFunctor Char)
type LiftScope = LocScope () SimpleInfo (LiftFunctor SimpleFunctor) Char
type LiftInnerBinder = BinderScope SimpleInfo LiftScope
type LiftOuterBinder = LiftBinder () SimpleInfo SimpleInfo SimpleFunctor Char
type LiftScopeResult = WithTracked Char LiftScope

lamLift :: Char -> LiftScope -> LiftScope
lamLift a = flip runColocated () . locScopeAbstract1 (SimpleInfoLam a) a

innerLamBinderLift :: Char -> LiftScope -> LiftInnerBinder
innerLamBinderLift a = locScopeInnerBinder1 (SimpleInfoLam a) a

boundLift :: Int -> LiftScope
boundLift = LocScopeBound ()

varLift :: Char -> LiftScope
varLift = pure

baseLift :: Char -> LiftScope
baseLift = LocScopeEmbed () . LiftFunctorBase . SimpleFunctorBase

freeVarsLift :: LiftScope -> Set Char
freeVarsLift = foldMap Set.singleton

trackedLift :: LiftScope -> Tracked Char
trackedLift = withTrackedState . locScopeLocation . trackScope

appLift :: LiftScope -> LiftScope -> LiftScope
appLift x y = LocScopeEmbed () (LiftFunctorBase (SimpleFunctorApp x y))

closureLift :: BinderId -> [Int] -> LiftScope
closureLift bid vars = LocScopeEmbed () (LiftFunctorClosure bid (Seq.fromList vars))

letLift :: Char -> LiftScope -> LiftScope -> LiftScope
letLift a x y =
  let y' = runColocated (locScopeAbstract1 (SimpleInfoLet a) a y) ()
  in LocScopeEmbed () (LiftFunctorBase (SimpleFunctorLet x y'))

outerLamBinderLift :: Int -> [Char] -> LiftInnerBinder -> LiftOuterBinder
outerLamBinderLift a = LiftBinder a . Set.fromList

shouldLiftSimple :: SimpleInfo -> Bool
shouldLiftSimple i =
  case i of
    SimpleInfoLam _ -> True
    SimpleInfoLet _ -> False

simpleLift :: SimpleScope -> SimpleLiftState LiftScopeResult
simpleLift s = predLiftLocScope shouldLiftSimple (trackScope (scopeAnno () s))
