{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : Network.TLS.QUIC
-- License     : BSD-style
-- Maintainer  : Vincent Hanquez <vincent@snarc.org>
-- Stability   : experimental
-- Portability : unknown
--
-- Experimental API to run the TLS handshake establishing a QUIC connection.
--
-- On the northbound API:
--
-- * QUIC starts a TLS client or server thread with 'newQUICClient' or
--   'newQUICServer'.
--
-- * QUIC executes and monitors the progress of the handshake with the
--   'ClientController' or 'ServerController' functions.  It sends continuation
--   messages and listens for the resulting status, success or failure.  At any
--   point it can decide to terminate the current handshake with constructors
--   'ExitClient' and 'ExitServer' .
--
-- The main steps of the handshake defined in the 'ClientController' /
-- 'ServerController' state machines are:
--
-- * @FinishedSent@: message Finished has been sent, endpoint is ready to send
--   application traffic
--
-- * @HandshakeComplete@: peer message Finished has been received and verified,
--   endpoint is ready to receive application traffic
--
-- * @HandshakeConfirmed@: TLS handshake is no more needed, session tickets have
--   all been transferred
--
-- Out of those three defined steps, only two are really used.  For a client,
-- steps @FinishedSent@ and @HandshakeComplete@ are the same.  For a server,
-- steps @HandshakeComplete@ and @HandshakeConfirmed@ are the same.
--
-- On the southbound API, TLS invokes QUIC callbacks to use the QUIC transport
-- protocol:
--
-- * TLS uses 'quicSend' and 'quicRecv' to send and receive handshake message
--   fragments.
--
-- * TLS calls 'quicInstallKeys' to provide to QUIC the traffic secrets it
--   should use for encryption/decryption.
--
-- * TLS calls 'quicNotifyExtensions' to notify to QUIC the transport parameters
--   exchanged through the handshake protocol.
--
module Network.TLS.QUIC (
    -- * Hash
      hkdfExpandLabel
    , hkdfExtract
    , hashDigestSize
    -- * Extensions
    , ExtensionRaw(..)
    , ExtensionID
    , extensionID_QuicTransportParameters
    -- * Secrets
    , ServerTrafficSecret(..)
    , ClientTrafficSecret(..)
    , EarlySecret
    , HandshakeSecret
    , ApplicationSecret
    , TrafficSecrets
    , EarlySecretInfo(..)
    , HandshakeSecretInfo(..)
    , ApplicationSecretInfo(..)
    -- * Client handshake controller
    , newQUICClient
    , ClientController
    , ClientControl(..)
    , ClientStatus(..)
    -- * Server handshake controller
    , newQUICServer
    , ServerController
    , ServerControl(..)
    , ServerStatus(..)
    -- * Common
    , CryptLevel(..)
    , KeyScheduleEvent(..)
    , QUICCallbacks(..)
    , NegotiatedProtocol
    , HandshakeMode13(..)
    , errorTLS
    , errorToAlertDescription
    , errorToAlertMessage
    , fromAlertDescription
    , toAlertDescription
    , quicMaxEarlyDataSize
    ) where

import Network.TLS.Backend
import Network.TLS.Context
import Network.TLS.Context.Internal
import Network.TLS.Core
import Network.TLS.Crypto (hashDigestSize)
import Network.TLS.Extension (extensionID_QuicTransportParameters)
import Network.TLS.Handshake.Common
import Network.TLS.Handshake.Control
import Network.TLS.Handshake.Server
import Network.TLS.Handshake.State
import Network.TLS.Handshake.State13
import Network.TLS.Imports
import Network.TLS.KeySchedule (hkdfExtract, hkdfExpandLabel)
import Network.TLS.Record.Layer
import Network.TLS.Record.State
import Network.TLS.Struct
import Network.TLS.Types

import Control.Concurrent
import qualified Control.Exception as E
import System.Mem.Weak

nullBackend :: Backend
nullBackend = Backend {
    backendFlush = return ()
  , backendClose = return ()
  , backendSend  = \_ -> return ()
  , backendRecv  = \_ -> return ""
  }

-- | Argument given to 'quicInstallKeys' when encryption material is available.
data KeyScheduleEvent
    = InstallEarlyKeys (Maybe EarlySecretInfo)
      -- ^ Key material and parameters for traffic at 0-RTT level
    | InstallHandshakeKeys HandshakeSecretInfo
      -- ^ Key material and parameters for traffic at handshake level
    | InstallApplicationKeys ApplicationSecretInfo
      -- ^ Key material and parameters for traffic at application level

-- | Callbacks implemented by QUIC and to be called by TLS at specific points
-- during the handshake.  TLS may invoke them from external threads but calls
-- are not concurrent.  Only a single callback function is called at a given
-- point in time.
data QUICCallbacks = QUICCallbacks
    { quicSend              :: [(CryptLevel, ByteString)] -> IO ()
      -- ^ Called by TLS so that QUIC sends one or more handshake fragments. The
      -- content transiting on this API is the plaintext of the fragments and
      -- QUIC responsability is to encrypt this payload with the key material
      -- given for the specified level and an appropriate encryption scheme.
      --
      -- The size of the fragments may exceed QUIC datagram limits so QUIC may
      -- break them into smaller fragments.
      --
      -- The handshake protocol sometimes combines content at two levels in a
      -- single flight.  The TLS library does its best to provide this in the
      -- same @quicSend@ call and with a multi-valued argument.  QUIC can then
      -- decide how to transmit this optimally.
    , quicRecv              :: CryptLevel -> IO (Either TLSError ByteString)
      -- ^ Called by TLS to receive from QUIC the next plaintext handshake
      -- fragment.  The argument specifies with which encryption level the
      -- fragment should be decrypted.
      --
      -- QUIC may return partial fragments to TLS.  TLS will then call
      -- @quicRecv@ again as long as necessary.  Note however that fragments
      -- must be returned in the correct sequence, i.e. the order the TLS peer
      -- emitted them.
      --
      -- The function may return an error to TLS if end of stream is reached or
      -- if a protocol error has been received, believing the handshake cannot
      -- proceed any longer.  If the TLS handshake protocol cannot recover from
      -- this error, the failure condition will be reported back to QUIC through
      -- the control interface.
    , quicInstallKeys       :: KeyScheduleEvent -> IO ()
      -- ^ Called by TLS when new encryption material is ready to be used in the
      -- handshake.  The next 'quicSend' or 'quicRecv' may now use the
      -- associated encryption level (although the previous level is also
      -- possible: directions Send/Recv do not change at the same time).
    , quicNotifyExtensions  :: [ExtensionRaw] -> IO ()
      -- ^ Called by TLS when QUIC-specific extensions have been received from
      -- the peer.
    }

getTxLevel :: Context -> IO CryptLevel
getTxLevel ctx = do
    (_, _, level, _) <- getTxState ctx
    return level

getRxLevel :: Context -> IO CryptLevel
getRxLevel ctx = do
    (_, _, level, _) <- getRxState ctx
    return level

prepare :: ((status -> IO ()) -> statusI -> IO ())
        -> IO (statusI -> IO (), IO status)
prepare processI = do
    mvar <- newEmptyMVar
    let sync a = let put = putMVar mvar in processI put a
        ask  = takeMVar mvar
    return (sync, ask)

newRecordLayer :: Context -> QUICCallbacks
               -> RecordLayer [(CryptLevel, ByteString)]
newRecordLayer ctx callbacks = newTransparentRecordLayer get send recv
  where
    get     = getTxLevel ctx
    send    = quicSend callbacks
    recv    = getRxLevel ctx >>= quicRecv callbacks

-- | Start a TLS handshake thread for a QUIC client.  The client will use the
-- specified TLS parameters and call the provided callback functions to send and
-- receive handshake data.
--
-- Execution and synchronization between the internal TLS thread and external
-- QUIC threads is done through the 'ClientController' interface returned.
newQUICClient :: ClientParams -> QUICCallbacks -> IO ClientController
newQUICClient cparams callbacks = do
    (sync, ask) <- prepare processI
    ctx <- contextNew nullBackend cparams
    let ctx' = updateRecordLayer rl ctx
          { ctxHandshakeSync = HandshakeSync sync (\_ -> return ())
          }
        rl = newRecordLayer ctx callbacks
        failed = sync . ClientHandshakeFailedI . getErrorCause
    tid <- forkIO $ E.handle failed $ do
        handshake ctx'
        void $ recvData ctx'
    wtid <- mkWeakThreadId tid
    return (quicClient wtid ask)

  where
    processI _ (SendClientHelloI mEarlySecInfo) =
        quicInstallKeys callbacks (InstallEarlyKeys mEarlySecInfo)
    processI _ (RecvServerHelloI handSecInfo) =
        quicInstallKeys callbacks (InstallHandshakeKeys handSecInfo)
    processI put (SendClientFinishedI exts appSecInfo) = do
        quicInstallKeys callbacks (InstallApplicationKeys appSecInfo)
        quicNotifyExtensions callbacks (filterQTP exts)
        put ClientHandshakeComplete
    processI put RecvSessionTicketI = put ClientRecvSessionTicket
    processI put (ClientHandshakeFailedI e) = put (ClientHandshakeFailed e)

    quicClient wtid _ ExitClient = do
        mtid <- deRefWeak wtid
        forM_ mtid killThread
        return ClientHandshakeDone
    quicClient _ ask _ = ask

-- | Start a TLS handshake thread for a QUIC server.  The server will use the
-- specified TLS parameters and call the provided callback functions to send and
-- receive handshake data.
--
-- Execution and synchronization between the internal TLS thread and external
-- QUIC threads is done through the 'ServerController' interface returned.
newQUICServer :: ServerParams -> QUICCallbacks -> IO ServerController
newQUICServer sparams callbacks = do
    (sync, ask) <- prepare processI
    ctx <- contextNew nullBackend sparams
    let ctx' = updateRecordLayer rl ctx
          { ctxHandshakeSync = HandshakeSync (\_ -> return ()) sync
          }
        rl = newRecordLayer ctx callbacks
        failed = sync . ServerHandshakeFailedI . getErrorCause
    tid <- forkIO $ E.handle failed $ do
        handshake ctx'
        void $ recvData ctx'
    wtid <- mkWeakThreadId tid
    return (quicServer wtid ask)

  where
    processI _ (SendServerHelloI exts mEarlySecInfo handSecInfo) = do
        quicInstallKeys callbacks (InstallEarlyKeys mEarlySecInfo)
        quicInstallKeys callbacks (InstallHandshakeKeys handSecInfo)
        quicNotifyExtensions callbacks (filterQTP exts)
    processI put (SendServerFinishedI appSecInfo) = do
        quicInstallKeys callbacks (InstallApplicationKeys appSecInfo)
        put ServerFinishedSent
    processI put SendSessionTicketI = put ServerHandshakeComplete
    processI put (ServerHandshakeFailedI e) = put (ServerHandshakeFailed e)

    quicServer wtid _ ExitServer = do
        mtid <- deRefWeak wtid
        forM_ mtid killThread
        return ServerHandshakeDone
    quicServer _ ask _ = ask

getErrorCause :: TLSException -> TLSError
getErrorCause (HandshakeFailed e) = e
getErrorCause (Terminated _ _ e) = e
getErrorCause e =
    let msg = "unexpected TLS exception: " ++ show e
     in Error_Protocol (msg, True, InternalError)

filterQTP :: [ExtensionRaw] -> [ExtensionRaw]
filterQTP = filter (\(ExtensionRaw eid _) -> eid == extensionID_QuicTransportParameters)

-- | Can be used by callbacks to signal an unexpected condition.  This will then
-- generate an "internal_error" alert in the TLS stack.
errorTLS :: String -> IO a
errorTLS msg = throwCore $ Error_Protocol (msg, True, InternalError)

-- | Return the alert that a TLS endpoint would send to the peer for the
-- specified library error.
errorToAlertDescription :: TLSError -> AlertDescription
errorToAlertDescription = snd . head . errorToAlert

-- | Encode an alert to the assigned value.
fromAlertDescription :: AlertDescription -> Word8
fromAlertDescription = valOfType

-- | Decode an alert from the assigned value.
toAlertDescription :: Word8 -> Maybe AlertDescription
toAlertDescription = valToType
