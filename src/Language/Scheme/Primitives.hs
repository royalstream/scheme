{-# LANGUAGE ExistentialQuantification #-}
module Language.Scheme.Primitives
  ( ioPrimitives
  , primitives
  ) where

import Control.Monad.Except
import qualified Data.Array.IArray as IArray
import           Data.CaseInsensitive  ( CI )
import qualified Data.CaseInsensitive as CI
import Data.Char ( toUpper, toLower, isAlpha, isDigit
                 , isUpper, isLower, isSpace, ord, chr )
import System.IO

import Language.Scheme.Parser
import Language.Scheme.Types

data Unpacker = forall a. Eq a => AnyUnpacker (LispVal -> ThrowsError a)

numericBinop :: (Integer -> Integer -> Integer) -> [LispVal] -> ThrowsError LispVal
numericBinop op singleVal@[_] = throwError $ NumArgs 2 singleVal
numericBinop op params = mapM unpackNum params >>= return . Number . foldl1 op

boolBinopCI :: CI.FoldCase a => (LispVal -> ThrowsError a) -> (a -> a -> Bool) -> [LispVal] -> ThrowsError LispVal
boolBinopCI unpacker op args = if length args /= 2
                                 then throwError $ NumArgs 2 args
                                 else do left <- unpacker $ args !! 0
                                         right <- unpacker $ args !! 1
                                         return $ Bool $ (CI.foldCase left) `op` (CI.foldCase right)

boolBinop :: (LispVal -> ThrowsError a) -> (a -> a -> Bool) -> [LispVal] -> ThrowsError LispVal
boolBinop unpacker op args = if length args /= 2
                             then throwError $ NumArgs 2 args
                             else do left <- unpacker $ args !! 0
                                     right <- unpacker $ args !! 1
                                     return $ Bool $ left `op` right

numBoolBinop :: (Integer -> Integer -> Bool) -> [LispVal] -> ThrowsError LispVal
numBoolBinop = boolBinop unpackNum

charBoolBinopCI :: (Char -> Char -> Bool) -> [LispVal] -> ThrowsError LispVal
charBoolBinopCI = boolBinopCI unpackChar

charBoolBinop :: (Char -> Char -> Bool) -> [LispVal] -> ThrowsError LispVal
charBoolBinop = boolBinop unpackChar

strBoolBinopCI :: (String -> String -> Bool) -> [LispVal] -> ThrowsError LispVal
strBoolBinopCI = boolBinopCI unpackStr

strBoolBinop :: (String -> String -> Bool) -> [LispVal] -> ThrowsError LispVal
strBoolBinop = boolBinop unpackStr

boolBoolBinop :: (Bool -> Bool -> Bool) -> [LispVal] -> ThrowsError LispVal
boolBoolBinop = boolBinop unpackBool

unpackNum :: LispVal -> ThrowsError Integer
unpackNum (Number n) = return n
unpackNum (String n) = let parsed = reads n in
                          if null parsed
                            then throwError $ TypeMismatch "number" $ String n
                            else return $ fst $ parsed !! 0
unpackNum (List [n]) = unpackNum n
unpackNum notNum = throwError $ TypeMismatch "number" notNum

unpackChar :: LispVal -> ThrowsError Char
unpackChar (Char c) = return c
unpackChar notChar = throwError $ TypeMismatch "char" notChar

unpackStr :: LispVal -> ThrowsError String
unpackStr (String s) = return s
unpackStr (Number s) = return $ show s
unpackStr (Bool s) = return $ show s
unpackStr notString = throwError $ TypeMismatch "string" notString

unpackBool :: LispVal -> ThrowsError Bool
unpackBool (Bool b) = return b
unpackBool notBool = throwError $ TypeMismatch "boolean" notBool

unpackEquals :: LispVal -> LispVal -> Unpacker -> ThrowsError Bool
unpackEquals arg1 arg2 (AnyUnpacker unpacker) =
             do unpacked1 <- unpacker arg1
                unpacked2 <- unpacker arg2
                return $ unpacked1 == unpacked2
        `catchError` (const $ return False)


car :: [LispVal] -> ThrowsError LispVal
car [List (x : xs)] = return x
car [DottedList (x : xs) _] = return x
car [badArg] = throwError $ TypeMismatch "pair" badArg
car badArgList = throwError $ NumArgs 1 badArgList

cdr :: [LispVal] -> ThrowsError LispVal
cdr [List (x : xs)] = return $ List xs
cdr [DottedList (_ : xs) x] = return $ DottedList xs x
cdr [DottedList [xs] x] = return x
cdr [badArg] = throwError $ TypeMismatch "pair" badArg
cdr badArgList = throwError $ NumArgs 1 badArgList

cons :: [LispVal] -> ThrowsError LispVal
cons [x1, List []] = return $ List [x1]
cons [x, List xs] = return $ List $ x : xs
cons [x, DottedList xs xlast] = return $ DottedList (x : xs) xlast
cons [x1, x2] = return $ DottedList [x1] x2
cons badArgList = throwError $ NumArgs 2 badArgList

equal :: [LispVal] -> ThrowsError LispVal
equal [arg1, arg2] = do
    primitiveEquals <- fmap or $ mapM (unpackEquals arg1 arg2)
                      [AnyUnpacker unpackNum, AnyUnpacker unpackStr, AnyUnpacker unpackBool]
    eqvEquals <- eqv [arg1, arg2]
    return $ Bool $ (primitiveEquals || let (Bool x) = eqvEquals in x)
equal badArgList = throwError $ NumArgs 2 badArgList

eqv :: [LispVal] -> ThrowsError LispVal
eqv [arg1, arg2] = return . Bool $ arg1 == arg2
eqv badArgList = throwError $ NumArgs 2 badArgList

isBoolean :: [LispVal] -> ThrowsError LispVal
isBoolean [(Bool _)] = return . Bool $ True
isBoolean [_]= return . Bool $ False
isBoolean badArgList = throwError $ NumArgs 1 badArgList

isPair :: [LispVal] -> ThrowsError LispVal
isPair [List (x:y:_)] = return . Bool $ True
isPair [DottedList _ _] = return . Bool $ True
isPair [_]= return . Bool $ False
isPair badArgList = throwError $ NumArgs 1 badArgList

isList :: [LispVal] -> ThrowsError LispVal
isList [List _] = return . Bool $ True
isList [_]= return . Bool $ False
isList badArgList = throwError $ NumArgs 1 badArgList

isSymbol :: [LispVal] -> ThrowsError LispVal
isSymbol [Atom _] = return . Bool $ True
isSymbol [_]= return . Bool $ False
isSymbol badArgList = throwError $ NumArgs 1 badArgList

symbolToString :: [LispVal] -> ThrowsError LispVal
symbolToString [Atom s] = return . String $ s
symbolToString [badArg]= throwError $ TypeMismatch "symbol" badArg
symbolToString badArgList = throwError $ NumArgs 1 badArgList

stringToSymbol :: [LispVal] -> ThrowsError LispVal
stringToSymbol [String s] = return . Atom $ s
stringToSymbol [badArg]= throwError $ TypeMismatch "string" badArg
stringToSymbol badArgList = throwError $ NumArgs 1 badArgList

isNumber :: [LispVal] -> ThrowsError LispVal
isNumber [Number _] = return . Bool $ True
isNumber [_]= return . Bool $ False
isNumber badArgList = throwError $ NumArgs 1 badArgList

isChar :: [LispVal] -> ThrowsError LispVal
isChar [Char _] = return . Bool $ True
isChar [_]= return . Bool $ False
isChar badArgList = throwError $ NumArgs 1 badArgList

isString :: [LispVal] -> ThrowsError LispVal
isString [String _] = return . Bool $ True
isString [_]= return . Bool $ False
isString badArgList = throwError $ NumArgs 1 badArgList

isVector :: [LispVal] -> ThrowsError LispVal
isVector [Vector _] = return . Bool $ True
isVector [_]= return . Bool $ False
isVector badArgList = throwError $ NumArgs 1 badArgList

listToVector :: [LispVal] -> ThrowsError LispVal
listToVector [List xs] = return . Vector $ IArray.listArray (0, length xs - 1) xs
listToVector [badArg]= throwError $ TypeMismatch "list" badArg
listToVector badArgList = throwError $ NumArgs 1 badArgList

vectorToList :: [LispVal] -> ThrowsError LispVal
vectorToList [Vector vs] = return . List $ IArray.elems vs
vectorToList [badArg]= throwError $ TypeMismatch "vector" badArg
vectorToList badArgList = throwError $ NumArgs 1 badArgList

isPort :: [LispVal] -> ThrowsError LispVal
isPort [Port _] = return . Bool $ True
isPort [_]= return . Bool $ False
isPort badArgList = throwError $ NumArgs 1 badArgList

isProcedure :: [LispVal] -> ThrowsError LispVal
isProcedure [PrimitiveFunc _] = return . Bool $ True
isProcedure [IOFunc _] = return . Bool $ True
isProcedure [Func _ _ _ _] = return . Bool $ True
isProcedure [_]= return . Bool $ False
isProcedure badArgList = throwError $ NumArgs 1 badArgList

charIsAlphabetic :: [LispVal] -> ThrowsError LispVal
charIsAlphabetic [Char c] = return . Bool $ isAlpha c
charIsAlphabetic [badArg]= throwError $ TypeMismatch "char" badArg
charIsAlphabetic badArgList = throwError $ NumArgs 1 badArgList

charIsNumeric :: [LispVal] -> ThrowsError LispVal
charIsNumeric [Char c] = return . Bool $ isDigit c
charIsNumeric [badArg]= throwError $ TypeMismatch "char" badArg
charIsNumeric badArgList = throwError $ NumArgs 1 badArgList

charIsWhitespace :: [LispVal] -> ThrowsError LispVal
charIsWhitespace [Char c] = return . Bool $ isSpace c
charIsWhitespace [badArg]= throwError $ TypeMismatch "char" badArg
charIsWhitespace badArgList = throwError $ NumArgs 1 badArgList

charIsUpperCase :: [LispVal] -> ThrowsError LispVal
charIsUpperCase [Char c] = return . Bool $ isUpper c
charIsUpperCase [badArg]= throwError $ TypeMismatch "char" badArg
charIsUpperCase badArgList = throwError $ NumArgs 1 badArgList

charIsLowerCase :: [LispVal] -> ThrowsError LispVal
charIsLowerCase [Char c] = return . Bool $ isLower c
charIsLowerCase [badArg]= throwError $ TypeMismatch "char" badArg
charIsLowerCase badArgList = throwError $ NumArgs 1 badArgList

charToInteger :: [LispVal] -> ThrowsError LispVal
charToInteger [Char c] = return . Number . fromIntegral . ord $ c
charToInteger [badArg]= throwError $ TypeMismatch "char" badArg
charToInteger badArgList = throwError $ NumArgs 1 badArgList

integerToChar :: [LispVal] -> ThrowsError LispVal
integerToChar [Number c] = return . Char . chr . fromIntegral $ c
integerToChar [badArg]= throwError $ TypeMismatch "number" badArg
integerToChar badArgList = throwError $ NumArgs 1 badArgList

charUpcase :: [LispVal] -> ThrowsError LispVal
charUpcase [Char c] = return . Char $ toUpper c
charUpcase [badArg]= throwError $ TypeMismatch "char" badArg
charUpcase badArgList = throwError $ NumArgs 1 badArgList

charDowncase :: [LispVal] -> ThrowsError LispVal
charDowncase [Char c] = return . Char $ toLower c
charDowncase [badArg]= throwError $ TypeMismatch "char" badArg
charDowncase badArgList = throwError $ NumArgs 1 badArgList

stringLength :: [LispVal] -> ThrowsError LispVal
stringLength [String s] = return . Number $ fromIntegral . length $ s
stringLength [badArg]= throwError $ TypeMismatch "string" badArg
stringLength badArgList = throwError $ NumArgs 1 badArgList

primitives :: [(String, [LispVal] -> ThrowsError LispVal)]
primitives = [("+", numericBinop (+)),
              ("-", numericBinop (-)),
              ("*", numericBinop (*)),
              ("/", numericBinop div),
              ("mod", numericBinop mod),
              ("quotient", numericBinop quot),
              ("remainder", numericBinop rem),
              ("=", numBoolBinop (==)),
              ("<", numBoolBinop (<)),
              (">", numBoolBinop (>)),
              ("/=", numBoolBinop (/=)),
              (">=", numBoolBinop (>=)),
              ("<=", numBoolBinop (<=)),
              ("&&", boolBoolBinop (&&)),
              ("||", boolBoolBinop (||)),
              ("string=?", strBoolBinop (==)),
              ("string<?", strBoolBinop (<)),
              ("string>?", strBoolBinop (>)),
              ("string<=?", strBoolBinop (<=)),
              ("string>=?", strBoolBinop (>=)),
              ("string-ci=?", strBoolBinopCI (==)),
              ("string-ci<?", strBoolBinopCI (<)),
              ("string-ci>?", strBoolBinopCI (>)),
              ("string-ci<=?", strBoolBinopCI (<=)),
              ("string-ci>=?", strBoolBinopCI (>=)),
              ("string-length", stringLength),
              ("char=?", charBoolBinop (==)),
              ("char<?", charBoolBinop (<)),
              ("char>?", charBoolBinop (>)),
              ("char<=?", charBoolBinop (<=)),
              ("char>=?", charBoolBinop (>=)),
              ("char-ci=?", charBoolBinopCI (==)),
              ("char-ci<?", charBoolBinopCI (<)),
              ("char-ci>?", charBoolBinopCI (>)),
              ("char-ci<=?", charBoolBinopCI (<=)),
              ("char-ci>=?", charBoolBinopCI (>=)),
              ("char-alphabetic?", charIsAlphabetic),
              ("char-numeric?", charIsNumeric),
              ("char-whitespace?", charIsWhitespace),
              ("char-upper-case?", charIsUpperCase),
              ("char-lower-case?", charIsLowerCase),
              ("char->integer", charToInteger),
              ("integer->char", integerToChar),
              ("char-upcase", charUpcase),
              ("char-downcase", charDowncase),
              ("car", car),
              ("cdr", cdr),
              ("cons", cons),
              ("eq?", eqv),
              ("eqv?", eqv),
              ("equal?", equal),
              ("boolean?", isBoolean),
              ("pair?", isPair),
              ("list?", isList),
              ("symbol?", isSymbol),
              ("symbol->string", symbolToString),
              ("string->symbol", stringToSymbol),
              ("number?", isNumber),
              ("char?", isChar),
              ("string?", isString),
              ("vector?", isVector),
              ("vector->list", vectorToList),
              ("list->vector", listToVector),
              ("port?", isPort),
              ("procedure?", isProcedure)]

-- FIXME: Add more IO primitives
ioPrimitives :: [(String, [LispVal] -> EvalM LispVal)]
ioPrimitives = [("open-input-file", makePort ReadMode),
                ("open-output-file", makePort WriteMode),
                ("close-input-port", closePort),
                ("close-output-port", closePort),
                ("read", readProc),
                ("write", writeProc),
                ("read-contents", readContents)]
-- FIXME: Add display function which prints the value to the stdout

makePort :: IOMode -> [LispVal] -> EvalM LispVal
makePort mode [String filename] = fmap Port $ liftIO $ openFile filename mode

closePort :: [LispVal] -> EvalM LispVal
closePort [Port port] = liftIO $ hClose port >> (return $ Bool True)
closePort _ = return $ Bool False

readProc :: [LispVal] -> EvalM LispVal
readProc [] = readProc [Port stdin]
readProc [Port port] = (liftIO $ hGetLine stdin) >>= liftThrows . readExpr

writeProc :: [LispVal] -> EvalM LispVal
writeProc [obj] = writeProc [obj, Port stdout]
writeProc [obj, Port port] = liftIO $ hPrint port obj >> (return $ Bool True)

readContents :: [LispVal] -> EvalM LispVal
readContents [String filename] = fmap String $ liftIO $ readFile filename