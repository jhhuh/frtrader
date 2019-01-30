{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RecursiveDo #-}

module Main where

import Reactive.Banana
import Reactive.Banana.Frameworks.Extended
import Pipes.Concurrent

import Test.Tasty
import Test.Tasty.HUnit

import Control.Concurrent.STM

import Strategy

import Market.Types ( Coin(..)
                    , BTC(..)
                    , USD(..)
                    , StrategyAdvice(..)
                    )

import Interface

import qualified Data.HashMap.Strict as H

--------------------------------------------------------------------------------
main :: IO ()
main = defaultMain $ tests (undefined :: Price BTC) (undefined :: Vol USD)
--------------------------------------------------------------------------------

tests :: forall p v q c. (Coin p, Coin v) => Price p -> Vol v -> TestTree
tests _ _ = testGroup " Trading Strategy Tests"
    [ testCase "copyBookStrategy" $ do
        outputPairs <- interpretFrameworks (selfUpdateState copyBookStrategy emptyState) (copyInEs :: [Maybe(TradingEv p v q c)])  
        let outputActions = fmap fst <$> outputPairs
        assertEqual "Output list does not match" copyExpectedAs (fmap removeReasoning <$> outputActions)

    , testCase "refillAsksStrategy" $ do
        outputPairs <- interpretFrameworks (selfUpdateState refillAsksStrategy refillInitialState) (refillInEs :: [Maybe(TradingEv p v q c)])
        let outputActions = fmap fst <$> outputPairs
            outputStates  = fmap snd <$> outputPairs
        assertEqual "Output list does not match"        refillExpectedAs (fmap removeReasoning <$> outputActions)
        assertEqual "Final output state does not match" refillFinalState (last outputStates)

    , testCase "exposureControl" $ do
        let exposureControl' = fmap (fmap (fmap (fmap (\action -> (mempty, action))))) exposureControl
        outputPairs <- interpretFrameworks
                            (selfUpdateState exposureControl' expoInitialState)
                            ((fmap snd expoOutInEs) :: [Maybe(TradingEv p v q c)])
        let outputStates = fmap snd <$> outputPairs
        assertEqual "Final output state does not match" 
            (fmap fst (expoOutInEs :: [(Maybe (Vol v), Maybe (TradingEv p v q c))]) ) (fmap realizedExposure <$> outputStates)

    , testCase "mirroringStrategy - Output/State" $ do
        outputEvents <- interpretFrameworks (uncurry mirroringStrategy . split) (binaryIns :: [Maybe (Either (TradingEv p v q c) (TradingEv p v q c))])  
        assertEqual "Output list does not match" binaryExpectedAs (fmap removeComments <$> outputEvents)

    , testCase "mirroringStrategy - Refill reissuance" $ do
        outputEvents <- interpretFrameworks (uncurry mirroringStrategy . split) (refillIssuanceIns :: [Maybe (Either (TradingEv p v q c) (TradingEv p v q c))])  
        assertEqual "Output list does not match" refillIssuanceExpectedAs (fmap removeComments <$> outputEvents)

    , testCase "mirroringStrategy - Cancellation \"placement\"  reissuance" $ do
        outputEvents <- interpretFrameworks (uncurry mirroringStrategy . split) (cancellationIssuanceIns :: [Maybe (Either (TradingEv p v q c) (TradingEv p v q c))])  
        assertEqual "Output list does not match" cancellationIssuanceExpectedAs (fmap removeComments <$> outputEvents)

    -- , testCase "mirroringStrategy - Cancellation cancel reissuance" $ do

    ]

removeReasoning :: StrategyAdvice a -> StrategyAdvice a
removeReasoning (Advice (r, a)) = Advice ("", a)

removeComments 
    :: ( Maybe (StrategyAdvice (Action p v)), Maybe (StrategyAdvice (Action p v)))
    -> ( Maybe (StrategyAdvice (Action p v)), Maybe (StrategyAdvice (Action p v)))
removeComments (a,b) = (fmap removeReasoning a, fmap removeReasoning b)

--------------------------------------------------------------------------------
-- FIX ME! Compiler requires this type signature. Why? Monomorphism?
qa1, qa2, qa3, qa4, qb1 :: forall p v q. (Coin p, Coin v) => Quote p v q 

qa1 = Quote Ask (Price 1000) (Vol 1) undefined
qa2 = Quote Ask (Price 2000) (Vol 1) undefined
qa3 = Quote Ask (Price 1000) (Vol 3) undefined
qa4 = Quote Ask (Price 1500) (Vol 1) undefined

qb1 = Quote Bid (Price  900) (Vol 1) undefined


-- FIX ME! Compiler requires this type signature. Why? Monomorphism?
bk1, bk2, bk3, bk4 :: forall p v q c. (Coin p, Coin v) => QuoteBook p v q c

bk1 = QuoteBook {bids = [qb1], asks = [qa1],     counter = undefined}
bk2 = QuoteBook {bids = [],    asks = [qa1,qa2], counter = undefined}
bk3 = QuoteBook {bids = [qb1], asks = [qa3,qa2], counter = undefined}
bk4 = QuoteBook {bids = [],    asks = [qa4,qa2], counter = undefined}

-- FIX ME! Compiler requires this type signature. Why? Monomorphism?
copyInEs :: forall p v q c. (Coin p, Coin v) => [Maybe (TradingEv p v q c)]
copyInEs = 
    [ Nothing
    , Just $ FillsEv  []
    , Just $ BookEv   bk1
    , Just $ PlaceEv  undefined 
    , Just $ BookEv   bk2
    , Nothing
    , Nothing
    , Just $ CancelEv (Just 333)
    , Just $ BookEv   bk3
    , Just $ PlaceEv  undefined
    , Just $ BookEv   bk4
    ]

-- FIX ME! Compiler requires this type signature. Why? Monomorphism?
copyExpectedAs :: forall p v. (Coin p, Coin v) => [Maybe (StrategyAdvice (Action p v))]
copyExpectedAs =
    [ Nothing
    , Nothing
    , Just $ Advice ("", ZipList [PlaceLimit Ask (Price 1000) (Vol 1) (Just 0)])
    , Nothing
    , Just $ Advice ("", ZipList [])
    , Nothing
    , Nothing
    , Nothing
    , Just $ Advice ("", ZipList [PlaceLimit Ask (Price 1000) (Vol 2) (Just 1)])
    , Nothing
    -- Cannot place new order because we are already at exposure limit. Must wait for `CancelEv`s first.
    , Just $ Advice ("", ZipList [{- PlaceLimit Ask (Price 1500) (Vol 1) (Just 2),-} CancelLimit 0, CancelLimit 1]) 
    ]

------------------------------------------------------------------------------
-- Action with ClientOID = Just 2 is somehow missing, but for this event to have been received from the framework, it
-- must be the case, that we created this order in the past (otherwise the event would not be dispatched to the strategy)
-- Thus, we will ask for a refill.
-- Is this the failure mode we want, though? "when in doubt, refill"
refillInEs :: forall p v q c. (Coin p, Coin v) => [Maybe (TradingEv p v q c)]
refillInEs = 
    [ Nothing
    , Just $ BookEv bk2
    , Just $ FillsEv [FillEv Ask (Price 1000) (Vol 1) (Just 0)]
    , Just $ PlaceEv Nothing
    , Just $ CancelEv (Just 7)
    , Nothing
    , Just $ FillsEv [FillEv Ask (Price 1000) (Vol 1) (Just 2)]
    , Just $ CancelEv (Just 444)
    , Just $ FillsEv [ FillEv Ask (Price 1500) (Vol 2) (Just 1)
                     , FillEv Ask (Price 1000) (Vol 3) (Just 0)]
    , Just $ CancelEv (Just 9)
    , Just $ DoneEv   (Just 0)
    ]

refillExpectedAs :: forall p v. (Coin p, Coin v) => [Maybe (StrategyAdvice (Action p v))]
refillExpectedAs =
    [ Nothing
    , Just mempty
    , Just $ Advice ("", ZipList [PlaceLimit Bid (Price 1000) (Vol 1) Nothing])
    , Just mempty
    , Just mempty
    , Nothing
    , Just $ Advice ("", ZipList [PlaceLimit Bid (Price 1000) (Vol 1) Nothing])
    , Just mempty
    , Just $ Advice ("", ZipList [ PlaceLimit Bid (Price 1500) (Vol 2) Nothing
                                 , PlaceLimit Bid (Price 1000) (Vol 3) Nothing])
    , Just mempty
    , Just mempty
    ]

refillInitialState :: forall p v. (Coin p, Coin v) => ActionState p v
refillInitialState = 
    ActionState
        { openActionsMap = H.fromList 
            [ ((Ask, Price 1000), H.singleton 0 (OpenAction {oaVolume = Vol 4, oaCancelled = False, oaExecdVol  = Vol 0}) )
            , ((Ask, Price 1500), H.singleton 1 (OpenAction {oaVolume = Vol 5, oaCancelled = False, oaExecdVol  = Vol 1}) )
            , ((Ask, Price 3000), H.fromList[(8, OpenAction {oaVolume = Vol 5, oaCancelled = False, oaExecdVol  = Vol 1})
                                            ,(9, OpenAction {oaVolume = Vol 7, oaCancelled = False, oaExecdVol  = Vol 5})])
            , ((Ask, Price 5000), H.singleton 7 (OpenAction {oaVolume = Vol 2, oaCancelled = False, oaExecdVol  = Vol 1}) )
            ]
        , nextCOID = 10
        , realizedExposure = Vol (0 :: v)
        }

refillFinalState :: forall p v. (Coin p, Coin v) => Maybe (ActionState p v)
refillFinalState = Just $
    ActionState
        { openActionsMap = H.fromList 
            [ ((Ask, Price 1500), H.singleton 1 (OpenAction {oaVolume = Vol 5, oaCancelled = False, oaExecdVol  = Vol 3}) )
            , ((Ask, Price 3000), H.singleton 8 (OpenAction {oaVolume = Vol 5, oaCancelled = False, oaExecdVol  = Vol 1}) )]
        , nextCOID = 10
        , realizedExposure = Vol (7 :: v)
        }

--------------------------------------------------------------------------------
expoInitialState :: forall p v. (Coin p, Coin v) => ActionState p v
expoInitialState =
    ActionState
        { openActionsMap = H.fromList 
            [ ((Ask, Price 1500), H.singleton 1 (OpenAction {oaVolume = Vol 5, oaCancelled = False, oaExecdVol  = Vol 3}) )
            , ((Ask, Price 3000), H.singleton 8 (OpenAction {oaVolume = Vol 5, oaCancelled = False, oaExecdVol  = Vol 1}) )]
        , nextCOID = 10
        , realizedExposure = Vol (6 :: v)
        }

-- FIX ME! Compiler requires this type signature. Why? Monomorphism?
expoOutInEs :: forall p v q c. (Coin p, Coin v) => [(Maybe (Vol v), Maybe (TradingEv p v q c))]
expoOutInEs =
   -- (realized exposure volume just after event, event) pairs
    [ (Nothing     , Just $ BookEv bk1)
    , (Just (Vol 6), Just $ FillsEv [])
    , (Nothing     , Just $ PlaceEv undefined)
    , (Nothing     , Nothing)
    , (Just (Vol 1), Just $ FillsEv [ FillEv Bid (Price 1500) (Vol 2) Nothing
                                    , FillEv Bid (Price 1000) (Vol 3) Nothing ])
    , (Nothing     , Just $ BookEv bk3)
    , (Nothing     , Just $ CancelEv (Just 333))
    , (Just (Vol 0), Just $ FillsEv [ FillEv Bid (Price 1500) (Vol 1) Nothing ])
    ]

--------------------------------------------------------------------------------
-- test for tracking the orderbook

binaryIns :: forall p v q c. (Coin p, Coin v) => [Maybe (Either (TradingEv p v q c) (TradingEv p v q c))]
binaryIns =
    [ Nothing
    , Just $ Left $ FillsEv  []
    , Just $ Left $ BookEv   bk1
    , Just $ Left $ PlaceEv  undefined
    , Just $ Left $ BookEv   bk2
    , Nothing
    , Just     $ Right $ FillsEv [FillEv Ask (Price 1000) (Vol 0.2) (Just 0)]
    , Just $ Left $ CancelEv (Just 333)
    , Just $ Left $ BookEv   bk3
    , Just $ Left $ PlaceEv  undefined
    , Just $ Left $ BookEv   bk4
    ]

-- The model adopted here is the one used by reactive-banana.
-- Each item on this list happened at a different time (in sequence).
-- The outer Maybe defines whether an event happened at this time or not, Nothing means time passed but nothing happened this instant.
-- the inner maybes specify whether there is something to do at this time on the corresponding market.
-- In other words, an output event has occurred and there should be something to do on at least one exchange.
-- the value: Just (Nothing, Nothing) is an "implementation glitch" and should never occur. 

binaryExpectedAs :: forall p v. (Coin p, Coin v) => [ Maybe ( Maybe (StrategyAdvice (Action p v)), Maybe (StrategyAdvice (Action p v)) )]
binaryExpectedAs =
    [ Nothing
    , Nothing
    , Just $ (Nothing, Just $ Advice ("", ZipList [PlaceLimit Ask (Price 1000) (Vol 1) (Just 0)]))
    , Nothing
    , Just $ (Nothing, Just $ Advice ("", ZipList []))
    , Nothing
    , Just $ (Just (Advice ("",ZipList {getZipList = [PlaceLimit Bid (Price 1000) (Vol 0.2) Nothing]})), Nothing)
    , Nothing
    , Just $ (Nothing, Just $ Advice ("", ZipList [PlaceLimit Ask (Price 1000) (Vol 2) (Just 1)]))
    , Nothing
    , Just $ (Nothing, Just $ Advice ("", ZipList [PlaceLimit Ask (Price 1500) (Vol 1) (Just 2), CancelLimit 0, CancelLimit 1 ]))
    ]


--------------------------------------------------------------------------------
-- test for unnecessary re-issuance of placement for target that has not yet been refilled.

refillIssuanceIns :: forall p v q c. (Coin p, Coin v) => [Maybe (Either (TradingEv p v q c) (TradingEv p v q c))]
refillIssuanceIns =
    [ Nothing
    , Just $ Left $ BookEv   bk3
    , Just     $ Right $ FillsEv [FillEv Ask (Price 1000) (Vol 0.2) (Just 0)]
    , Just $ Left $ BookEv   bk3  -- no exposure available
    , Just $ Left $ FillsEv [FillEv Bid (Price 1000) (Vol 0.2) Nothing]
    , Just $ Left $ BookEv   bk3  -- now re-issue target
    , Just $ Left $ BookEv   bk4  -- clear old levels
    ]

refillIssuanceExpectedAs :: forall p v. (Coin p, Coin v) => [ Maybe ( Maybe (StrategyAdvice (Action p v)), Maybe (StrategyAdvice (Action p v)) )]
refillIssuanceExpectedAs =
    [ Nothing
    , Just $ (Nothing, Just $ Advice ("", ZipList [PlaceLimit Ask (Price 1000) (Vol 3) (Just 0)]))
    , Just $ (Just (Advice ("",ZipList {getZipList = [PlaceLimit Bid (Price 1000) (Vol 0.2) Nothing]})), Nothing)
    , Just $ (Nothing, Just $ Advice ("", ZipList []))
    , Nothing
    , Just $ (Nothing, Just $ Advice ("", ZipList [PlaceLimit Ask (Price 1000) (Vol 0.2) (Just 1)]))
    , Just $ (Nothing, Just $ Advice ("",ZipList {getZipList =
                                                  [ PlaceLimit {aSide = Ask, aPrice = Price 1500.00000000, aVol = Vol 1.00, amCOID = Just (COID 2)}
                                                  , CancelLimit {aCOID = COID 0}
                                                  , CancelLimit {aCOID = COID 1}
                                                  ]}))
    ]


--------------------------------------------------------------------------------
-- test for unnecessary re-issuance of placement for target that has been cancelled.

cancellationIssuanceIns :: forall p v q c. (Coin p, Coin v) => [Maybe (Either (TradingEv p v q c) (TradingEv p v q c))]
cancellationIssuanceIns =
    [ Nothing
    , Just $ Left $ BookEv   bk3
    , Just $ Left $ BookEv   bk4  -- no more orders at $1000
    , Just     $ Right $ FillsEv [FillEv Ask (Price 1000) (Vol 3) (Just 0)]
    , Just $ Left $ BookEv   bk3
    , Just     $ Right $ CancelEv (Just 0)
    ]

cancellationIssuanceExpectedAs :: forall p v. (Coin p, Coin v) => [ Maybe ( Maybe (StrategyAdvice (Action p v)), Maybe (StrategyAdvice (Action p v)) )]
cancellationIssuanceExpectedAs =
    [ Nothing
    , Just $ (Nothing, Just $ Advice ("", ZipList [PlaceLimit Ask (Price 1000) (Vol 3) (Just 0)]))
    , Just $ (Nothing, Just $ Advice ("", ZipList {getZipList =
                                                    [ PlaceLimit {aSide = Ask, aPrice = Price 1500, aVol = Vol 1, amCOID = Just (COID 1)}
                                                    , CancelLimit {aCOID = COID 0}
                                                    ]}))
    , Just $ (Just (Advice ("",ZipList {getZipList = [PlaceLimit Bid (Price 1000) (Vol 3) Nothing]})), Nothing)
    , Just $ (Nothing, Just $ Advice ("", ZipList []))
    ]


--------------------------------------------------------------------------------
-- test for unnecessary re-issuance of cancellation for target that has been cancelled.


--------------------------------------------------------------------------------
-- test for, placing an exposure limited order and then later automatically placing remaining orders 
-- after receiving `CancelEv` and no longer being limited by exposure.
