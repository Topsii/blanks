module Test.Blanks.BlanksTest where

import Blanks
import Control.Monad.Identity (Identity (..))
import Data.Set (Set)
import qualified Data.Set as Set
import Test.Blanks.Assertions ((@/=))
import Test.Tasty
import Test.Tasty.HUnit

type BareScope = PureScope (NameOnly Char) Identity Char

abst :: Char -> BareScope -> BareScope
abst a = blankAbstract1 (Name a ()) a

bound :: Int -> BareScope
bound = PureScope . ScopeT . pure . UnderBoundScope . BoundScope

var :: Char -> BareScope
var = pure

freeVars :: BareScope -> Set Char
freeVars = foldMap Set.singleton

test_sub :: TestTree
test_sub =
  let svar = var 'x'
      sbound = bound 0
      sfree = abst 'y' (var 'x')
      sfree2 = abst 'z' (abst 'y' (var 'x'))
      sid = abst 'x' (var 'x')
      swonky = abst 'x' (bound 0)
      sconst = abst 'x' (abst 'y' (var 'x'))
      sflip = abst 'x' (abst 'y' (var 'y'))
      svar2 = var 'e'
      swonky2 = abst 'x' svar2

      testEq =
        testCase "eq" $ do
          svar @?= svar
          svar @/= svar2
          sid @?= abst 'x' (var 'x')
          sid @?= abst 'y' (var 'y')
          sid @/= abst 'x' (var 'y')
          sid @/= abst 'y' (var 'x')
          sid @/= svar

      testFreeVars =
        testCase "free vars" $ do
          freeVars svar @?= Set.singleton 'x'
          freeVars sbound @?= Set.empty
          freeVars sfree @?= Set.singleton 'x'
          freeVars sfree2 @?= Set.singleton 'x'
          freeVars sid @?= Set.empty
          freeVars swonky @?= Set.empty
          freeVars sconst @?= Set.empty
          freeVars sflip @?= Set.empty
          freeVars svar2 @=? Set.singleton 'e'
          freeVars swonky2 @?= Set.singleton 'e'

      testInstantiate =
        testCase "instantiate" $ do
          blankInstantiate1 svar2 svar @?= svar
          blankInstantiate1 svar2 sbound @?= svar2
          blankInstantiate1 svar2 sid @?= sid
          blankInstantiate1 svar2 swonky @?= swonky2

      testApply =
        testCase "apply" $ do
          blankApply1 svar2 sid @?= Right svar2
          blankApply1 svar2 swonky @?= Right sbound
          blankApply1 svar2 sconst @?= Right swonky2
          blankApply1 svar2 sflip @?= Right sid

      testVarSub =
        testCase "var sub" $ do
          (svar >>= const svar2) @?= svar2
          (sfree >>= const svar2) @?= abst 'y' svar2
          (sfree2 >>= const svar2) @?= abst 'c' (abst 'd' svar2)

      testIdSub =
        testCase "id sub" $ do
          (svar >>= const sid) @?= sid
          (sfree >>= const sid) @?= abst 'y' sid
          (sfree2 >>= const sid) @?= abst 'c' (abst 'd' sid)

   in testGroup "sub" [testEq, testFreeVars, testInstantiate, testApply, testVarSub, testIdSub]
