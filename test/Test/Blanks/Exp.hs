{-# LANGUAGE DeriveAnyClass #-}

module Test.Blanks.Exp
  ( Ident (..)
  , CExp (..)
  , cexpLoc
  , CDecl (..)
  , declKeywords
  , expKeywords
  , cexpParser
  , runCExpParser
  , cdeclParser
  , runCDeclParser
  , Exp (..)
  , ExpScope
  , DeclScope
  , ExpLocScope
  , DeclLocScope
  , declLocScopeForget
  , declScopeAnno
  , expToNameless
  , expToNamed
  , declToNameless
  , declToNamed
  ) where

import Blanks (LocScope, pattern LocScopeBinder, pattern LocScopeBound, pattern LocScopeEmbed, pattern LocScopeFree,
               Located (..), NameOnly, pattern NameOnly, Scope, locScopeAbstract1, locScopeForget, locScopeUnAbstract1,
               runColocated, scopeAnno)
import Control.DeepSeq (NFData)
import Control.Monad (when)
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Generics (Generic)
import Test.Blanks.Parsing

-- A newtype indicating an identifier in our language
newtype Ident = Ident { unIdent :: String } deriving newtype (Eq, Show, Ord, NFData)

-- The type of concrete expressions, labeled with source location
data CExp l =
    CExpBool !l !Bool
  | CExpInt !l !Int
  | CExpApp !l !(CExp l) !(CExp l)
  | CExpAdd !l !(CExp l) !(CExp l)
  | CExpIf !l !(CExp l) !(CExp l) !(CExp l)
  | CExpIsZero !l !(CExp l)
  | CExpVar !l !Ident
  | CExpAbs !l !Ident !(CExp l)
  | CExpAsc !l !(CExp l) !(CExp l)
  | CExpTyInt !l
  | CExpTyBool !l
  | CExpTyFun !l !(CExp l) !(CExp l)
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- Extracts the location from a concrete expression
cexpLoc :: CExp l -> l
cexpLoc ce =
  case ce of
    CExpBool l _ -> l
    CExpInt l _ -> l
    CExpApp l _ _ -> l
    CExpAdd l _ _ -> l
    CExpIf l _ _ _ -> l
    CExpIsZero l _ -> l
    CExpVar l _ -> l
    CExpAbs l _ _ -> l
    CExpAsc l _ _ -> l
    CExpTyInt l -> l
    CExpTyBool l -> l
    CExpTyFun l _ _ -> l

expKeywords :: Set Ident
expKeywords = Set.fromList $ fmap Ident
  [ "#t"
  , "#f"
  , "+"
  , "if"
  , "zero?"
  , ":"
  , "lambda"
  , "int"
  , "bool"
  , "->"
  ]

declKeywords :: Set Ident
declKeywords = Set.fromList $ fmap Ident
  [ "declare"
  , "define"
  ]

nonKeywordParser :: Parser Ident
nonKeywordParser = do
  rawIdent <- identifier
  let ident = Ident rawIdent
  when (Set.member ident expKeywords) (fail ("Parsed exp keyword: " <> rawIdent))
  when (Set.member ident declKeywords) (fail ("Parsed decl keyword: " <> rawIdent))
  pure ident

-- Parses a concrete expression from a string
cexpParser :: Parser (CExp SourceSpan)
cexpParser = result where
  result = branch
    [ trueParser
    , falseParser
    , intParser
    , addParser
    , ifParser
    , isZeroParser
    , absParser
    , appParser
    , ascParser
    , tyBoolParser
    , tyIntParser
    , tyFunParser
    , varParser
    ]

  trueParser = around (const . flip CExpBool True) (symbol "#t")

  falseParser = around (const . flip CExpBool False) (symbol "#f")

  intParser = around CExpInt signed

  addParser = around2 CExpAdd (parens (symbol "+" *> double cexpParser))

  ifParser = around3 CExpIf (parens (symbol "if" *> triple cexpParser))

  isZeroParser = around CExpIsZero (parens (symbol "zero?" *> cexpParser))

  absParser = around2 CExpAbs $ parens $ do
    _ <- symbol "lambda"
    n <- parens nonKeywordParser
    b <- cexpParser
    pure (n, b)

  appParser = around2 CExpApp (parens (double cexpParser))

  ascParser = around2 CExpAsc (parens (symbol ":" *> double cexpParser))

  tyBoolParser = around (const . CExpTyBool) (symbol "bool")

  tyIntParser = around (const . CExpTyInt) (symbol "int")

  tyFunParser = around2 (CExpTyFun) (parens (symbol "->" *> double cexpParser))

  varParser = around CExpVar nonKeywordParser

runCExpParser :: String -> IO (CExp SourceSpan)
runCExpParser = runParserIO cexpParser

data Level =
    LevelTerm
  | LevelType
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data CDecl l = CDecl !l !Level !Ident !(CExp l)
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- Parses a concrete declaration from a string
cdeclParser :: Parser (CDecl SourceSpan)
cdeclParser = result where
  result = branch
    [ parser "declare" LevelType
    , parser "define" LevelTerm
    ]

  parser name lvl = around2 (flip CDecl lvl) (parens (symbol name *> ((,) <$> nonKeywordParser <*> cexpParser)))

runCDeclParser :: String -> IO (CExp SourceSpan)
runCDeclParser = runParserIO cexpParser

-- Just the expressions of our language that have nothing to do with naming
data Exp a =
    ExpBool !Bool
  | ExpInt !Int
  | ExpApp a a
  | ExpAdd a a
  | ExpIf a a a
  | ExpIsZero a
  | ExpAsc a a
  | ExpTyBool
  | ExpTyInt
  | ExpTyFun a a
  deriving stock (Eq, Show, Functor, Foldable, Traversable, Generic)
  deriving anyclass (NFData)

data Decl a = Decl !Level !Ident a
  deriving stock (Eq, Show, Functor, Foldable, Traversable, Generic)
  deriving anyclass (NFData)

-- An ExpScope without locations
type ExpScope a = Scope (NameOnly Ident) Exp a

type DeclScope a = Decl (ExpScope a)

-- A nameless equivalent to 'CExp'
type ExpLocScope l a = LocScope l (NameOnly Ident) Exp a

type DeclLocScope l a = Located l (Decl (ExpLocScope l a))

declLocScopeForget :: DeclLocScope l a -> DeclScope a
declLocScopeForget = fmap locScopeForget . locatedVal

declScopeAnno :: l -> DeclScope a -> DeclLocScope l a
declScopeAnno l = Located l . fmap (scopeAnno l)

-- Convert to nameless representation
expToNameless :: CExp l -> ExpLocScope l Ident
expToNameless ce =
  case ce of
    CExpBool l b -> LocScopeEmbed l (ExpBool b)
    CExpInt l i -> LocScopeEmbed l (ExpInt i)
    CExpApp l a b -> LocScopeEmbed l (ExpApp (expToNameless a) (expToNameless b))
    CExpAdd l a b -> LocScopeEmbed l (ExpAdd (expToNameless a) (expToNameless b))
    CExpIf l a b c -> LocScopeEmbed l (ExpIf (expToNameless a) (expToNameless b) (expToNameless c))
    CExpIsZero l a -> LocScopeEmbed l (ExpIsZero (expToNameless a))
    CExpVar l x -> LocScopeFree l x
    CExpAbs l x a -> runColocated (locScopeAbstract1 (NameOnly x) x (expToNameless a)) l
    CExpAsc l a b -> LocScopeEmbed l (ExpAsc (expToNameless a) (expToNameless b))
    CExpTyInt l -> LocScopeEmbed l ExpTyInt
    CExpTyBool l -> LocScopeEmbed l ExpTyBool
    CExpTyFun l a b -> LocScopeEmbed l (ExpTyFun (expToNameless a) (expToNameless b))

-- Convert back to named representation. Usually this isn't a necessary operation,
-- but we want to do round-trip testing
expToNamed :: ExpLocScope l Ident -> Maybe (CExp l)
expToNamed e =
  case e of
    LocScopeBound _ _ -> Nothing
    LocScopeFree l a -> pure (CExpVar l a)
    LocScopeBinder l _ (NameOnly x) b -> CExpAbs l x <$> expToNamed (locScopeUnAbstract1 x b)
    LocScopeEmbed l fe ->
      case fe of
        ExpBool b -> pure (CExpBool l b)
        ExpInt i -> pure (CExpInt l i)
        ExpApp a b -> CExpApp l <$> expToNamed a <*> expToNamed b
        ExpAdd a b -> CExpAdd l <$> expToNamed a <*> expToNamed b
        ExpIf a b c -> CExpIf l <$> expToNamed a <*> expToNamed b <*> expToNamed c
        ExpIsZero a -> CExpIsZero l <$> expToNamed a
        ExpAsc a b -> CExpAsc l <$> expToNamed a <*> expToNamed b
        ExpTyInt -> pure (CExpTyInt l)
        ExpTyBool -> pure (CExpTyBool l)
        ExpTyFun a b -> CExpTyFun l <$> expToNamed a <*> expToNamed b

declToNameless :: CDecl l -> DeclLocScope l Ident
declToNameless (CDecl l lvl i e) = Located l (Decl lvl i (expToNameless e))

declToNamed :: DeclLocScope l Ident -> Maybe (CDecl l)
declToNamed (Located l (Decl lvl i e)) = fmap (CDecl l lvl i) (expToNamed e)