{-# LANGUAGE OverloadedStrings #-}
module System.FilePath.ByteString
  ( FilePath
  , isAbsolute
  , splitFileName
  , canonicalizePath
  , canonicalizePathAsRelative
  , dropTrailingPathSeparator, addTrailingPathSeparator
  , (</>), (<.>)
  , takeDirectory, takeFileName
  , makeRelative
  , exists
  ) where

import           Control.Exception (catch, throwIO)
import           Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as BS8
import           Data.Maybe (fromMaybe)
import           Data.Monoid
import           GHC.IO.Exception (IOErrorType(..))
import           System.IO.Error (ioeGetErrorType)
import qualified System.Posix.ByteString as Posix

import           Prelude.Compat hiding (FilePath)

type FilePath = Posix.RawFilePath

unprefixed :: ByteString -> ByteString -> Maybe ByteString
unprefixed prefix full
  | prefix `BS8.isPrefixOf` full = Just $ BS8.drop (BS8.length prefix) full
  | otherwise = Nothing

{-# INLINE exists #-}
exists :: FilePath -> IO Bool
exists path
  | BS8.null path = return True
  | otherwise = Posix.fileExist path `catch`
    \e ->
    case ioeGetErrorType e of
    InappropriateType -> return False
    _ -> throwIO e

splitPath :: FilePath -> [FilePath]
splitPath path
  | isAbsolute path = "/" : BS8.split '/' (BS8.tail path)
  | otherwise = BS8.split '/' path

joinPath :: [FilePath] -> FilePath
joinPath (path:paths) | path == "/" = "/" <> BS8.intercalate "/" paths
joinPath       paths                =        BS8.intercalate "/" paths

onFst :: (a -> a') -> (a, b) -> (a', b)
onFst f (x, y) = (f x, y)

splitFileName :: FilePath -> (FilePath, ByteString)
splitFileName = onFst joinPath . f . splitPath
  where
    f [] = ([], "")
    f [x] = ([], x)
    f (x:xs) = onFst (x:) $ f xs

takeDirectory :: FilePath -> FilePath
takeDirectory = joinPath . reverse . drop 1 . reverse . splitPath

takeFileName :: FilePath -> FilePath
takeFileName path =
  case splitPath path of
  [] -> ""
  xs -> last xs

removeRedundantComponents :: FilePath -> FilePath
removeRedundantComponents =
  joinPath .
  foldr step [] .
  filter (/= ".") .
  splitPath
  where
    step "/" xs = "/" : xs
    step ".." xs = ".." : xs
    step _ ("..":xs) = xs
    step x xs = x:xs

dropTrailingPathSeparator :: FilePath -> FilePath
dropTrailingPathSeparator x
  | "/" `BS8.isSuffixOf` x = BS8.init x
  | otherwise = x

addTrailingPathSeparator :: FilePath -> FilePath
addTrailingPathSeparator x
  | "/" `BS8.isSuffixOf` x = x
  | otherwise = x <> "/"

(</>) :: FilePath -> FilePath -> FilePath
"." </> y = y
"" </> y = y
x </> y
  | isAbsolute y = y
  | otherwise = dropTrailingPathSeparator x <> "/" <> y

(<.>) :: FilePath -> ByteString -> FilePath
f <.> g = f <> "." <> g

isAbsolute :: FilePath -> Bool
isAbsolute = ("/" `BS8.isPrefixOf`)

makeRelative :: FilePath -> FilePath -> FilePath
makeRelative prefix full =
  case unprefixed prefix' full' of
  Nothing -> full
  Just suffix -> fromMaybe suffix $ unprefixed "/" suffix
  where
    prefix' = dropTrailingPathSeparator prefix
    full' = dropTrailingPathSeparator full

canonicalizePath :: FilePath -> FilePath -> FilePath
canonicalizePath curDir path =
  dropTrailingPathSeparator $ removeRedundantComponents $ curDir </> path

canonicalizePathAsRelative :: FilePath -> FilePath -> FilePath
canonicalizePathAsRelative curDir = makeRelative curDir . canonicalizePath curDir
