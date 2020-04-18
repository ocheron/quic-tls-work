{-# LANGUAGE OverloadedStrings #-}

module Network.QUIC.Sender (
    sender
  , resender
  ) where

import Control.Concurrent
import qualified Data.ByteString as B

import Network.QUIC.Connection
import Network.QUIC.Exception
import Network.QUIC.Imports
import Network.QUIC.Packet
import Network.QUIC.Types

----------------------------------------------------------------

cryptoFrame :: Connection -> CryptoData -> EncryptionLevel -> IO Frame
cryptoFrame conn crypto lvl = do
    let len = B.length crypto
    off <- getCryptoOffset conn lvl len
    return $ Crypto off crypto

----------------------------------------------------------------

construct :: Connection
          -> EncryptionLevel
          -> [Frame]
          -> [PacketNumber]  -- Packet number history
          -> Maybe Int       -- Packet size
          -> IO [ByteString]
construct conn lvl frames pns mTargetSize = do
    ver <- getVersion conn
    token <- getToken conn
    mycid <- getMyCID conn
    peercid <- getPeerCID conn
    established <- isConnectionEstablished conn
    if established || (isServer conn && lvl == HandshakeLevel) then
        constructTargetPacket ver mycid peercid mTargetSize token
      else do
        bss0 <- constructLowerAckPacket lvl ver mycid peercid token
        let total = sum (map B.length bss0)
            mTargetSize' = subtract total <$> mTargetSize
        bss1 <- constructTargetPacket ver mycid peercid mTargetSize' token
        return (bss0 ++ bss1)
  where
    constructLowerAckPacket HandshakeLevel ver mycid peercid token = do
        ppns <- getPeerPacketNumbers conn InitialLevel
        if nullPeerPacketNumbers ppns then
            return []
          else do
            -- This packet will not be acknowledged.
            clearPeerPacketNumbers conn InitialLevel
            mypn <- getPacketNumber conn
            let header   = Initial ver peercid mycid token
                ackFrame = Ack (toAckInfo $ fromPeerPacketNumbers ppns) 0
                plain    = Plain (Flags 0) mypn [ackFrame]
                ppkt     = PlainPacket header plain
            qlogSent conn ppkt
            encodePlainPacket conn ppkt Nothing
    constructLowerAckPacket RTT1Level ver mycid peercid _ = do
        ppns <- getPeerPacketNumbers conn HandshakeLevel
        if nullPeerPacketNumbers ppns then
            return []
          else do
            -- This packet will not be acknowledged.
            clearPeerPacketNumbers conn HandshakeLevel
            mypn <- getPacketNumber conn
            let header   = Handshake ver peercid mycid
                ackFrame = Ack (toAckInfo $ fromPeerPacketNumbers ppns) 0
                plain    = Plain (Flags 0) mypn [ackFrame]
                ppkt     = PlainPacket header plain
            qlogSent conn ppkt
            encodePlainPacket conn ppkt Nothing
    constructLowerAckPacket _ _ _ _ _ = return []
    constructTargetPacket ver mycid peercid mlen token = do
        mypn <- getPacketNumber conn
        ppns <- getPeerPacketNumbers conn lvl
        let frames'
              | nullPeerPacketNumbers ppns = frames
              | otherwise   = Ack (toAckInfo $ fromPeerPacketNumbers ppns) 0 : frames
        let frames'' = case mlen of
              Nothing -> frames'
              Just _  -> frames' ++ [Padding 0] -- for qlog
        let ppkt = case lvl of
              InitialLevel   -> PlainPacket (Initial   ver peercid mycid token) (Plain (Flags 0) mypn frames'')
              RTT0Level      -> PlainPacket (RTT0      ver peercid mycid)       (Plain (Flags 0) mypn frames'')
              HandshakeLevel -> PlainPacket (Handshake ver peercid mycid)       (Plain (Flags 0) mypn frames'')
              RTT1Level      -> PlainPacket (Short         peercid)             (Plain (Flags 0) mypn frames'')
        if any ackEliciting frames then
            keepPlainPacket conn (mypn:pns) ppkt lvl ppns
          else
            clearPeerPacketNumbers conn lvl
        qlogSent conn ppkt
        encodePlainPacket conn ppkt mlen

----------------------------------------------------------------

sender :: Connection -> SendMany -> IO ()
sender conn send = handleLog logAction $ forever
    (takeOutput conn >>= sendOutput conn send)
  where
    logAction msg = connDebugLog conn ("sender: " ++ msg)

sendOutput :: Connection -> SendMany -> Output ->IO ()
sendOutput conn send (OutHndClientHello ch mEarlyData) = do
    sendCryptoFragment conn send ch InitialLevel
    case mEarlyData of
      Nothing -> return ()
      Just (sid,earlyData) -> do
          off <- getStreamOffset conn sid $ B.length earlyData
          bss1 <- construct conn RTT0Level [Stream sid off earlyData True] [] $ Just maximumQUICPacketSize
          send bss1
sendOutput conn send (OutHndServerHello sh sf) = do
    frame0 <- cryptoFrame conn sh InitialLevel
    bss0 <- construct conn InitialLevel [frame0] [] Nothing
    -- 824 = 1024 - 200 (size of sh)
    -- but 900 is good enough...
    let (sf1,sf2) = B.splitAt 824 sf
    let size = maximumQUICPacketSize - sum (map B.length bss0)
    frame1 <- cryptoFrame conn sf1 HandshakeLevel
    bss1 <- construct conn HandshakeLevel [frame1] [] $ Just size
    send (bss0 ++ bss1)
    sendCryptoFragment conn send sf2 HandshakeLevel
sendOutput conn send (OutHndServerHelloR sh) = do
    frame <- cryptoFrame conn sh InitialLevel
    bss <- construct conn InitialLevel [frame] [] $ Just maximumQUICPacketSize
    send bss
sendOutput conn send (OutHndClientFinished cf) = do
    -- fixme size
    frame <- cryptoFrame conn cf HandshakeLevel
    bss <- construct conn HandshakeLevel [frame] [] $ Just maximumQUICPacketSize
    send bss
sendOutput conn send (OutHndServerNST nst) = do
    frame <- cryptoFrame conn nst RTT1Level
    bss <- construct conn RTT1Level [frame] [] $ Just maximumQUICPacketSize
    send bss
sendOutput conn send (OutControl lvl frames) = do
    bss <- construct conn lvl frames [] $ Just maximumQUICPacketSize
    send bss
sendOutput conn send (OutStream sid dat fin) = do
    sendStreamFragment conn send sid dat fin
sendOutput conn send (OutShutdown sid) = do
    off <- getStreamOffset conn sid 0
    let frame = Stream sid off "" True
    bss <- construct conn RTT1Level [frame] [] $ Just maximumQUICPacketSize
    send bss
sendOutput conn send (OutPlainPacket (PlainPacket hdr0 plain0) pns) = do
    let lvl = packetEncryptionLevel hdr0
    let frames = filter retransmittable $ plainFrames plain0
    bss <- construct conn lvl frames pns $ Just maximumQUICPacketSize
    send bss

sendCryptoFragment :: Connection -> SendMany -> ByteString -> EncryptionLevel -> IO ()
sendCryptoFragment conn send bs0 lvl = loop bs0
  where
    loop "" = return ()
    loop bs = do
        let (target,rest) = B.splitAt 1024 bs
        frame <- cryptoFrame conn target lvl
        bss <- construct conn lvl [frame] [] $ Just maximumQUICPacketSize
        send bss
        loop rest

sendStreamFragment :: Connection -> SendMany -> StreamId -> ByteString -> Bool -> IO ()
sendStreamFragment conn send sid dat0 fin0 = do
    closed <- getStreamFin conn sid
    if closed then
        connDebugLog conn $ "Stream " ++ show sid ++ " is already closed."
      else do
        loop dat0
        when fin0 $ setStreamFin conn sid
  where
    loop "" = return ()
    loop dat = do
        let (target,rest) = B.splitAt 1024 dat
        off <- getStreamOffset conn sid $ B.length target
        let fin = fin0 && rest == ""
            frame = Stream sid off dat fin
        bss <- construct conn RTT1Level [frame] [] $ Just maximumQUICPacketSize
        send bss
        loop rest

----------------------------------------------------------------

resender :: Connection -> IO ()
resender conn = handleIOLog cleanupAction logAction $ forever $ do
    threadDelay 100000
    ppktpns <- getRetransmissions conn (MilliSeconds 600)
    established <- isConnectionEstablished conn
    -- Some implementations do not return Ack for Initial and Handshake
    -- correctly. We should consider that the success of handshake
    -- implicitly acknowledge them.
    let ppktpns'
         | established = filter isRTTxLevel ppktpns
         | otherwise   = ppktpns
    mapM_ put ppktpns'
    ppns <- getPeerPacketNumbers conn RTT1Level
    when (ppns /= emptyPeerPacketNumbers) $ do
        -- generating ACK
        putOutput conn $ OutControl RTT1Level []
  where
    cleanupAction = putInput conn $ InpError ConnectionIsClosed
    logAction msg = connDebugLog conn ("resender: " ++ msg)
    put (ppkt,pns) = putOutput conn $ OutPlainPacket ppkt pns

isRTTxLevel :: (PlainPacket,[PacketNumber]) -> Bool
isRTTxLevel (PlainPacket hdr _,_) = lvl == RTT1Level || lvl == RTT0Level
  where
    lvl = packetEncryptionLevel hdr
