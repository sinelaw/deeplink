{-# LANGUAGE OverloadedStrings #-}
-- | Deeplink's main module.
--
-- Wraps the DeepLink with optparse based option parsing and invokes
-- the given command.
{-# LANGUAGE CPP #-}
module Main (main) where

import           Control.Monad (liftM, when, forM_)
import           Data.Maybe (fromMaybe)
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8
import qualified DeepLink
import           Options.Applicative
import           System.FilePath.ByteString (FilePath)
import qualified System.Posix.ByteString as Posix
import           System.Process (callProcess)
import           System.IO (withFile, IOMode(..))
import           Prelude.Compat hiding (FilePath)

data Opts = Opts
  { _ldCommand :: String
  , _oPaths :: [FilePath]
  , _verbose :: Bool
  , _dryRun :: Bool
  , _generateDot :: Maybe FilePath
  } deriving Show

#ifdef OPTPARSE_OLD_VERSION
bytestr :: Monad m => String -> m ByteString
bytestr = liftM BS8.pack . str
#else
bytestr :: ReadM ByteString
bytestr = liftM BS8.pack str
#endif

desc :: String
desc =
    unlines
    [ "Recursively scans for dependencies in .o files (specified via "
    , "DEEPLINK__ADD_* macros in a C compilation) from a specified root set "
    , "of .o files.  Gives the result to a specified command (e.g: \"ld\" or "
    , "\"echo\")."
    ]

getOpts :: IO Opts
getOpts =
  execParser $
  info (helper <*> parser) $
  fullDesc
  <> progDesc desc
  <> header "deeplink - deeply link a target"
  where
    parser =
      Opts
      <$> strOption
          (long "ld" <> help "ld command to use" <>
           metavar "ld-command")
      <*> some (argument bytestr (metavar "opaths" <> help "At least one root .o path"))
      <*> switch (long "verbose" <> short 'v' <> help "Verbose mode")
      <*> switch (long "dry-run" <> short 'd' <> help "Dry run (won't execute the command)")
      <*> optional (option bytestr (metavar "DOTFILE" <> long "graph" <> short 'g' <> help "Generate dependency graph (in GraphViz dot format)"))

-- TODO: add escaping, etc.
quote :: ByteString -> ByteString
quote x = "\"" <> x <> "\""

main :: IO ()
main = do
  -- setNumCapabilities . (*2) =<< getNumProcessors -- To get full reasonable buildsome parallelism
  Opts ldCommand oPaths verbose dryRun genDot <- getOpts
  cwd <- Posix.getWorkingDirectory
  (dependencies, fullList) <- DeepLink.deepLink cwd oPaths
  let cmd@(cmdExec:cmdArgs) = words ldCommand ++ map BS8.unpack fullList
  when verbose $ putStrLn $ unwords cmd
  when (not dryRun) $ callProcess cmdExec cmdArgs
  case genDot of
      Nothing -> return ()
      Just dotFilePath -> do
          withFile (BS8.unpack dotFilePath) WriteMode $ \handle -> do
              BS8.hPutStrLn handle "digraph G {"
              forM_ dependencies $ \(parent, child) -> BS8.hPutStrLn handle $ "\t" <> quote (fromMaybe "commandline" parent) <> " -> " <> quote child
              BS8.hPutStrLn handle "}"
  return ()
