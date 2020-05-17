{-# LANGUAGE OverloadedStrings #-}

module HandshakeSpec where

import Control.Concurrent.Async
import Control.Monad
import Data.IORef
import Data.List
import Network.TLS hiding (TLSException(..))
import Test.Hspec

import Network.QUIC

spec :: Spec
spec = do
    describe "handshake" $ do
        it "can handshake in the normal case" $ do
            let cc = defaultClientConfig
                sc = defaultServerConfig
            testHandshake cc sc FullHandshake
        it "can handshake in the case of TLS hello retry" $ do
            let cc = defaultClientConfig
                sc = defaultServerConfig {
                       scConfig = defaultConfig {
                                    confGroups = [P256]
                                  }
                     }
            testHandshake cc sc HelloRetryRequest
        it "can handshake in the case of QUIC retry" $ do
            let cc = defaultClientConfig
                sc = defaultServerConfig {
                       scRequireRetry = True
                     }
            testHandshake cc sc FullHandshake
        it "can handshake in the case of resumption" $ do
            smgr <- newSessionManager
            let cc = defaultClientConfig
                sc = defaultServerConfig {
                       scSessionManager = smgr
                     }
            testHandshake2 cc sc (FullHandshake, PreSharedKey) False
        it "can handshake in the case of 0-RTT" $ do
            smgr <- newSessionManager
            let cc = defaultClientConfig
                sc = defaultServerConfig {
                       scSessionManager = smgr
                     , scEarlyDataSize  = 1024
                     }
            testHandshake2 cc sc (FullHandshake, RTT0) True
        it "fails with unknown server certificate" $ do
            let cc1 = defaultClientConfig {
                        ccValidate = True  -- ouch, default should be reversed
                      }
                cc2 = defaultClientConfig
                sc  = defaultServerConfig
                certificateRejected e
                    | HandshakeFailed m <- e = "certificate rejected" `isInfixOf` m
                    | otherwise = False
            testHandshake3 cc1 cc2 sc certificateRejected
        it "fails with no group in common" $ do
            let cc1 = defaultClientConfig {
                        ccConfig = defaultConfig { confGroups = [X25519] }
                      }
                cc2 = defaultClientConfig {
                        ccConfig = defaultConfig { confGroups = [P256] }
                      }
                sc  = defaultServerConfig {
                        scConfig = defaultConfig { confGroups = [P256] }
                      }
                handshakeFailure e
                    | HandshakeFailed m <- e = "HandshakeFailure" `isInfixOf` m
                    | otherwise = False
            testHandshake3 cc1 cc2 sc handshakeFailure

testHandshake :: ClientConfig -> ServerConfig -> HandshakeMode13 -> IO ()
testHandshake cc sc mode = void $ concurrently client server
  where
    sc' = sc {
            scKey  = "test/serverkey.pem"
          , scCert = "test/servercert.pem"
          }
    client = runQUICClient cc $ \conn -> do
        isConnectionOpen conn `shouldReturn` True
        waitEstablished conn
        handshakeMode <$> getConnectionInfo conn `shouldReturn` mode
    server = runQUICServer sc' $ \conn -> do
        isConnectionOpen conn `shouldReturn` True
        waitEstablished conn
        handshakeMode <$> getConnectionInfo conn `shouldReturn` mode
        stopQUICServer conn

testHandshake2 :: ClientConfig -> ServerConfig -> (HandshakeMode13, HandshakeMode13) -> Bool -> IO ()
testHandshake2 cc1 sc (mode1, mode2) use0RTT = void $ concurrently client server
  where
    sc' = sc {
            scKey  = "test/serverkey.pem"
          , scCert = "test/servercert.pem"
          }
    runClient cc mode = runQUICClient cc $ \conn -> do
        isConnectionOpen conn `shouldReturn` True
        waitEstablished conn
        handshakeMode <$> getConnectionInfo conn `shouldReturn` mode
        getResumptionInfo conn
    client = do
        res <- runClient cc1 mode1
        let cc2 = cc1 { ccResumption = res
                      , ccUse0RTT    = use0RTT
                      }
        void $ runClient cc2 mode2
    server = do
        ref <- newIORef (0 :: Int)
        runQUICServer sc' $ \conn -> do
            isConnectionOpen conn `shouldReturn` True
            waitEstablished conn
            n <- readIORef ref
            if n >= 1 then stopQUICServer conn else writeIORef ref (n + 1)

testHandshake3 :: ClientConfig -> ClientConfig -> ServerConfig -> (QUICError -> Bool) -> IO ()
testHandshake3 cc1 cc2 sc selector = void $ concurrently clients server
  where
    sc' = sc {
            scKey  = "test/serverkey.pem"
          , scCert = "test/servercert.pem"
          }
    clients = do
        let query content conn = do
                isConnectionOpen conn `shouldReturn` True
                waitEstablished conn
                s <- stream conn
                sendStream s content
        runQUICClient cc1 (query "first") `shouldThrow` selector
        runQUICClient cc2 (query "second") `shouldReturn` ()
    server = runQUICServer sc' $ \conn -> do
        isConnectionOpen conn `shouldReturn` True
        waitEstablished conn
        Right s <- acceptStream conn
        recvStream s 1024 `shouldReturn` "second"
        stopQUICServer conn

newSessionManager :: IO SessionManager
newSessionManager = sessionManager <$> newIORef Nothing

sessionManager :: IORef (Maybe (SessionID, SessionData)) -> SessionManager
sessionManager ref = SessionManager {
    sessionEstablish      = establish
  , sessionResume         = resume
  , sessionResumeOnlyOnce = resume
  , sessionInvalidate     = \_ -> return ()
  }
  where
    establish sid sdata = writeIORef ref $ Just (sid,sdata)
    resume sid = do
        mx <- readIORef ref
        case mx of
          Nothing -> return Nothing
          Just (s,d)
            | s == sid  -> return $ Just d
            | otherwise -> return Nothing
