#!/usr/bin/env stack
-- stack --install-ghc ghci --package recursion-schemes --package containers --package fgl --package mtl --package graphviz --package text --resolver nightly-2019-01-03

{-# LANGUAGE DeriveFunctor                  #-}
{-# LANGUAGE ExistentialQuantification      #-}
{-# LANGUAGE FlexibleContexts               #-}
{-# LANGUAGE InstanceSigs                   #-}
{-# LANGUAGE LambdaCase                     #-}
{-# LANGUAGE PatternSynonyms                #-}
{-# LANGUAGE RankNTypes                     #-}
{-# LANGUAGE ScopedTypeVariables            #-}
{-# LANGUAGE TypeFamilies                   #-}
{-# LANGUAGE ViewPatterns                   #-}
{-# OPTIONS_GHC -Wall                       #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

import           Control.Monad.State               (State, state, evalState)
import           Data.Char                         (isSpace)
import           Data.Functor.Foldable
import           Data.Graph.Inductive.PatriciaTree (Gr)
import           Data.GraphViz                     (GraphvizParams(..))
import           Data.List                         (foldl')
import           Data.Map                          (Map)
import           Data.Maybe                        (fromMaybe, isJust, isNothing)
import qualified Data.Graph.Inductive.Graph        as G
import qualified Data.GraphViz                     as GV
import qualified Data.GraphViz.Attributes.HTML     as HTML
import qualified Data.GraphViz.Printing            as GV
import qualified Data.Map                          as M
import qualified Data.Text.Lazy                    as T

data Trie  k v   = MkT  (Maybe v) (Map k (Trie k v))
  deriving Show

data TrieF k v x = MkTF (Maybe v) (Map k x         )
  deriving (Functor, Show)

type instance Base (Trie k v) = TrieF k v

instance Recursive (Trie k v) where
    project :: Trie k v -> TrieF k v (Trie k v)
    project (MkT v xs) = MkTF v xs

instance Corecursive (Trie k v) where
    embed :: TrieF k v (Trie k v) -> Trie k v
    embed (MkTF v xs) = MkT v xs

testTrie :: Trie Char Int
testTrie = MkT Nothing $ M.fromList [
      ('t', MkT Nothing $ M.fromList [
          ('o', MkT (Just 9) $ M.fromList [
              ( 'n', MkT (Just 3) M.empty )
            ]
          )
        , ('a', MkT Nothing $ M.fromList [
              ( 'x', MkT (Just 2) M.empty )
            ]
          )
        ]
      )
    ]

count :: Trie k v -> Int
count = cata countAlg

countAlg :: TrieF k v Int -> Int
countAlg (MkTF v subtrieCounts)
    | isJust v  = 1 + subtrieTotal
    | otherwise = subtrieTotal
  where
    subtrieTotal = sum subtrieCounts

trieSum :: Num a => Trie k a -> a
trieSum = cata trieSumAlg

trieSumAlg :: Num a => TrieF k a a -> a
trieSumAlg (MkTF v subtrieSums) = fromMaybe 0 v + sum subtrieSums

trieSumExplicit :: Num a => Trie k a -> a
trieSumExplicit (MkT v subtries) =
    fromMaybe 0 v + sum (fmap trieSumExplicit subtries)

trieSumCata :: Num a => Trie k a -> a
trieSumCata = cata $ \(MkTF v subtrieSums) ->
    fromMaybe 0 v + sum subtrieSums

lookup
    :: Ord k
    => [k]
    -> Trie k v
    -> Maybe v
lookup ks t = cata lookupperAlg t ks

lookupperAlg
    :: Ord k
    => TrieF k v ([k] -> Maybe v)
    -> ([k] -> Maybe v)
lookupperAlg (MkTF v lookuppers) = \case
    []   -> v
    k:ks -> case M.lookup k lookuppers of
      Nothing        -> Nothing
      Just lookupper -> lookupper ks

cata' :: (TrieF k v a -> a) -> Trie k v -> a
cata' alg = alg . fmap (cata' alg) . project

newtype MuTrie k v = MkMT (forall a. (TrieF k v a -> a) -> a)

cataMuTrie :: (TrieF k v a -> a) -> MuTrie k v -> a
cataMuTrie alg (MkMT f) = f alg

trieMuTrie :: Trie k v -> MuTrie k v
trieMuTrie t = MkMT $ flip cata t

muTrieTrie :: MuTrie k v -> Trie k v
muTrieTrie (MkMT f) = f embed

singleton :: [k] -> v -> Trie k v
singleton k v = ana (mkSingletonCoalg v) k

mkSingletonCoalg :: v -> ([k] -> TrieF k v [k])
mkSingletonCoalg v = singletonCoalg
  where
    singletonCoalg []     = MkTF (Just v) M.empty
    singletonCoalg (k:ks) = MkTF Nothing  (M.singleton k ks)

fromMap
    :: Ord k
    => Map [k] v
    -> Trie k v
fromMap = ana fromMapCoalg

fromMapCoalg
    :: Ord k
    => Map [k] v
    -> TrieF k v (Map [k] v)
fromMapCoalg mp = MkTF (M.lookup [] mp)
                       (M.fromListWith M.union
                          [ (k   , M.singleton ks v)
                          | (k:ks, v) <- M.toList mp
                          ]
                       )

ana' :: (a -> TrieF k v a) -> a -> Trie k v
ana' coalg = embed . fmap (ana' coalg) . coalg

data NuTrie k v = forall a. MkNT (a -> TrieF k v a) a

anaNuTrie :: (a -> TrieF k v a) -> a -> NuTrie k v 
anaNuTrie = MkNT

trieNuTrie :: Trie k v -> NuTrie k v
trieNuTrie = MkNT project

nuTrieTrie :: NuTrie k v -> Trie k v
nuTrieTrie (MkNT f x) = ana f x

fresh :: State Int Int
fresh = state $ \i -> (i, i+1)

trieGraph
    :: Trie k v
    -> Gr (Maybe v) k
trieGraph = flip evalState 0 . cata trieGraphAlg

trieGraphAlg
    :: TrieF k v (State Int (Gr (Maybe v) k))
    -> State Int (Gr (Maybe v) k)
trieGraphAlg (MkTF v xs) = do
    n         <- fresh
    subgraphs <- sequence xs
    --  subbroots :: [(k, Int)]
    let subroots = M.toList . fmap (fst . G.nodeRange) $ subgraphs
    pure $ G.insEdges ((\(k,i) -> (n,i,k)) <$> subroots)   -- insert root-to-subroots
         . G.insNode (n, v)                     -- insert new root
         . M.foldr (G.ufold (G.&)) G.empty      -- merge all subgraphs
         $ subgraphs

mapToGraph
    :: Ord k
    => Map [k] v
    -> Gr (Maybe v) k
mapToGraph = flip evalState 0 . hylo trieGraphAlg fromMapCoalg

hylo'
    :: (TrieF k v b -> b)   -- ^ an algebra
    -> (a -> TrieF k v a)   -- ^ a coalgebra
    -> a
    -> b
hylo' consume build = consume
                    . fmap (hylo' consume build)
                    . build

memeMap :: String -> Map String HTML.Label
memeMap = M.fromList . map (uncurry processLine . span (/= ',')) . lines
  where
    processLine qt (drop 1->img) = (
          filter (not . isSpace) qt
        , HTML.Table (HTML.HTable Nothing [] [r1,r2])
        )
      where
        r1 = HTML.Cells [HTML.LabelCell [] (HTML.Text [HTML.Str (T.pack qt)])]
        r2 = HTML.Cells [HTML.ImgCell   [] (HTML.Img [HTML.Src img])]

graphDot
    :: Gr (Maybe HTML.Label) String
    -> T.Text
graphDot = GV.printIt . GV.graphToDot params
  where
    params = GV.nonClusteredParams
      { fmtNode = \(_,  l) -> case l of
          Nothing -> [GV.shape GV.PointShape]
          Just l' -> [GV.toLabel l', GV.shape GV.PlainText]
      , fmtEdge = \(_,_,l) -> [GV.toLabel (concat ["[", l, "]"])]
      }

memeDot
    :: String
    -> T.Text
memeDot = graphDot
        . compactify
        . flip evalState 0
        . hylo trieGraphAlg fromMapCoalg
        . memeMap

compactify
    :: Gr (Maybe v) k
    -> Gr (Maybe v) [k]
compactify g0 = foldl' go (G.emap (:[]) g0) (G.labNodes g0)
  where
    go g (i, v) = case (G.inn g i, G.out g i) of
      ([(j, _, lj)], [(_, k, lk)])
        | isNothing v -> G.insEdge (j, k, lj ++ lk)
                       . G.delNode i . G.delEdges [(j,i),(i,k)]
                       $ g
      _               -> g
