{-# LANGUAGE RecordWildCards #-}

module Network.QUIC.Connection.Misc (
    setVersion
  , getVersion
  , setThreadIds
  , clearThreads
  , getSockInfo
  , setSockInfo
  ) where

import Control.Concurrent
import Data.IORef
import Network.Socket
import System.Mem.Weak

import Network.QUIC.Connection.Types
import Network.QUIC.Types

----------------------------------------------------------------

setVersion :: Connection -> Version -> IO ()
setVersion Connection{..} ver = writeIORef quicVersion ver

getVersion :: Connection -> IO Version
getVersion Connection{..} = readIORef quicVersion

----------------------------------------------------------------

setThreadIds :: Connection -> [ThreadId] -> IO ()
setThreadIds Connection{..} tids = do
    wtids <- mapM mkWeakThreadId tids
    writeIORef threadIds wtids

clearThreads :: Connection -> IO ()
clearThreads Connection{..} = do
    wtids <- readIORef threadIds
    mapM_ kill wtids
    writeIORef threadIds []
  where
    kill wtid = do
        mtid <- deRefWeak wtid
        case mtid of
          Nothing  -> return ()
          Just tid -> killThread tid

----------------------------------------------------------------

getSockInfo :: Connection -> IO (Socket, RecvQ)
getSockInfo Connection{..} = readIORef sockInfo

setSockInfo :: Connection -> (Socket, RecvQ) -> IO ()
setSockInfo Connection{..} si = writeIORef sockInfo si
