module Test.Blanks.TrackedTest
  ( testTracked
  ) where

import Blanks (mkTrackedBound, mkTrackedFree)
import Test.Blanks.SimpleScope (sbound, sconst, sflip, sfree, sfree2, sid, spair, svar, svar2, swonky, swonky2, swonky3,
                                tracked)
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (testCase, (@?=))

testTracked :: TestTree
testTracked = testCase "tracked" $ do
  tracked svar @?= mkTrackedFree 'x'
  tracked sbound @?= mkTrackedBound 0
  tracked sfree @?= mkTrackedFree 'x'
  tracked sfree2 @?= mkTrackedFree 'x'
  tracked sid @?= mempty
  tracked swonky @?= mkTrackedBound 0
  tracked sconst @?= mempty
  tracked sflip @?= mempty
  tracked svar2 @?= mkTrackedFree 'e'
  tracked swonky2 @?= mkTrackedFree 'e'
  tracked spair @?= mkTrackedFree 'x' <> mkTrackedBound 0
  tracked swonky3 @?= mkTrackedBound 3
