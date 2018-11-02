#!/usr/bin/env stack
-- stack --install-ghc ghci --resolver nightly-2018-11-02 --package singletons --package decidable --package lens-typelevel

{-# LANGUAGE AllowAmbiguousTypes            #-}
{-# LANGUAGE DataKinds                      #-}
{-# LANGUAGE EmptyCase                      #-}
{-# LANGUAGE FlexibleInstances              #-}
{-# LANGUAGE GADTs                          #-}
{-# LANGUAGE InstanceSigs                   #-}
{-# LANGUAGE KindSignatures                 #-}
{-# LANGUAGE LambdaCase                     #-}
{-# LANGUAGE MultiParamTypeClasses          #-}
{-# LANGUAGE NoStarIsType                   #-}
{-# LANGUAGE RankNTypes                     #-}
{-# LANGUAGE ScopedTypeVariables            #-}
{-# LANGUAGE StandaloneDeriving             #-}
{-# LANGUAGE TemplateHaskell                #-}
{-# LANGUAGE TypeApplications               #-}
{-# LANGUAGE TypeFamilies                   #-}
{-# LANGUAGE TypeInType                     #-}
{-# LANGUAGE TypeOperators                  #-}
{-# LANGUAGE TypeSynonymInstances           #-}
{-# LANGUAGE UndecidableInstances           #-}
{-# OPTIONS_GHC -Wall                       #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

import           Data.Kind
import           Data.Singletons
import           Data.Singletons.Prelude
import           Data.Singletons.Sigma
import           Data.Singletons.TH
import           Data.Singletons.TypeLits
import           Data.Type.Lens
import           Data.Type.Predicate

$(singletons [d|
  data Piece = PX | PO
    deriving (Eq, Ord)
  
  type Board = [[Maybe Piece]]

  emptyBoard :: Board
  emptyBoard = [[Nothing, Nothing, Nothing]
               ,[Nothing, Nothing, Nothing]
               ,[Nothing, Nothing, Nothing]
               ]

  altP :: Piece -> Piece
  altP PX = PO
  altP PO = PX
  |])

$(singletonsOnly [d|
  placeBoard :: N -> N -> Piece -> Board -> Board
  placeBoard i j p = set (ixList i . ixList j) (Just p)
  |])


altP_cyclic :: Sing p -> AltP (AltP p) :~: p
altP_cyclic SPX = Refl @'PX
altP_cyclic SPO = Refl @'PO

data InPlay :: Predicate Board

data GameState :: Piece -> Board -> Type where
    -- | The empty board is a valid state
    GSStart
        :: GameState 'PX EmptyBoard
    -- | We can also construct a valid game state if we have:
    GSUpdate
        :: forall p b1 b2. ()
        => InPlay          @@ b1     -- ^ a proof that b1 is in play
        -> Update    p        b1 b2  -- ^ a valid update
        -> GameState p        b1     -- ^ a proof that p, b1 are a valid state
        -- ---------------------------- then
        -> GameState (AltP p)    b2  -- ^ AltP p, b2 is a valid satte

data Sel :: N -> [k] -> k -> Type where
    -- | The first item in a list is at index ''Z'
    SelZ :: Sel 'Z (a ': as) a
    SelS :: Sel n  as        a      -- ^ If item @a@ is at index @n@ in list @as@
         -- ---------------------------- then
         -> Sel ('S n) (b ': bs) a  -- ^ Item @a@ is at index @''S' n@ in list @b ': bs@

data Coord :: (N, N) -> [[k]] -> k -> Type where
    (:$:) :: forall i j rows row p. ()
          => Sel i rows row
          -> Sel j row  p
          -> Coord '(i, j) rows p

data Update :: Piece -> Board -> Board -> Type where
    MkUpdate :: forall i j p b. ()
             => Coord '(i, j) b 'Nothing
             -> Update p b (PlaceBoard i j p b)
