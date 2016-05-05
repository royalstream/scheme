module Main where

import Control.Monad.IO.Class
import Data.Foldable
import Data.Maybe
import System.Console.Haskeline
import System.Environment

import Language.Scheme

until_ :: Monad m => (a -> Bool) -> m a -> (a -> m ()) -> m ()
until_ pred prompt action = do
  result <- prompt
  if pred result
     then return ()
     else action result >> until_ pred prompt action

replLoop :: InputT IO ()
replLoop = do
    env <- liftIO newEnv
    res <- liftIO $ loadStandardLibrary env
    case res of
      Left e  -> liftIO $ putStrLn "Error loading stdlib"
      Right _ -> until_ quitPred (getInputLine "Lisp>>> ") (evalAndPrint env . fromJust)
  where
    quitPred Nothing = True
    quitPred (Just "quit") = True
    quitPred _ = False

    evalAndPrint env str = do
      evalResult <- liftIO $ evalString env str
      case evalResult of
        Left  e     -> (outputStrLn . show) e
        Right exprs -> traverse_ (outputStrLn . show) exprs

    loadStandardLibrary env =
      evalLispVal env (List [Atom "load", String "lib/stdlib.scm"])

runRepl :: IO ()
runRepl = runInputT defaultSettings replLoop

main :: IO ()
main = do args <- getArgs
          if null args then runRepl else runOne $ args
