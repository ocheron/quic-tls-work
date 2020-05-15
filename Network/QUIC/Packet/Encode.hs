module Network.QUIC.Packet.Encode (
    encodePacket
  , encodeVersionNegotiationPacket
  , encodeRetryPacket
  , encodePlainPacket
  , maximumQUICPacketSize
  ) where

import qualified Data.ByteString as B
import Foreign.Ptr

import Network.QUIC.Connection
import Network.QUIC.Imports
import Network.QUIC.Packet.Frame
import Network.QUIC.Packet.Header
import Network.QUIC.Packet.Number
import Network.QUIC.Packet.Version
import Network.QUIC.TLS
import Network.QUIC.Types

----------------------------------------------------------------

-- minimum PMTU = 1024 + 256 = 1280
-- IPv4 payload = 1280 - 20 - 8 = 1252
-- IPv6 payload = 1280 - 40 - 8 = 1232

-- Short = (1 + 160 + 4) + (1 + 4 + 4) + 1024 = 1198  (padlen = 2)

maximumQUICPacketSize :: Int
maximumQUICPacketSize = 1200

-- Not from spec. retry token is 128 sometime.
maximumQUICHeaderSize :: BufferSize
maximumQUICHeaderSize = 256

----------------------------------------------------------------

-- | This is not used internally.
encodePacket :: Connection -> PacketO -> IO [ByteString]
encodePacket _    (PacketOV pkt) = (:[]) <$> encodeVersionNegotiationPacket pkt
encodePacket _    (PacketOR pkt) = (:[]) <$> encodeRetryPacket pkt
encodePacket conn (PacketOP pkt) = encodePlainPacket conn pkt Nothing

----------------------------------------------------------------

encodeVersionNegotiationPacket :: VersionNegotiationPacket -> IO ByteString
encodeVersionNegotiationPacket (VersionNegotiationPacket dCID sCID vers) = withWriteBuffer maximumQUICHeaderSize $ \wbuf -> do
    -- fixme: randomizing unused bits
    let Flags flags = versionNegotiationPacketType
    write8 wbuf flags
    -- ver .. sCID
    encodeLongHeader wbuf Negotiation dCID sCID
    -- vers
    mapM_ (write32 wbuf . encodeVersion) vers
    -- no header protection

----------------------------------------------------------------

encodeRetryPacket :: RetryPacket -> IO ByteString
encodeRetryPacket (RetryPacket ver dCID sCID token (Left odCID)) = withWriteBuffer maximumQUICHeaderSize $ \wbuf -> do
    save wbuf
    -- fixme: randomizing unused bits
    let Flags flags = retryPacketType
    write8 wbuf flags
    encodeLongHeader wbuf ver dCID sCID
    copyByteString wbuf token
    siz <- savingSize wbuf
    pseudo0 <- extractByteString wbuf $ negate siz
    let tag = calculateIntegrityTag odCID pseudo0
    copyByteString wbuf tag
    -- no header protection
encodeRetryPacket _ = error "encodeRetryPacket"

----------------------------------------------------------------

encodePlainPacket :: Connection -> PlainPacket -> Maybe Int -> IO [ByteString]
encodePlainPacket conn ppkt mlen = do
    wbuf <- newWriteBuffer (headerBuffer conn) (headerBufferSize conn)
    encodePlainPacket' conn wbuf ppkt mlen

encodePlainPacket' :: Connection -> WriteBuffer -> PlainPacket -> Maybe Int -> IO [ByteString]
encodePlainPacket' conn wbuf (PlainPacket (Initial ver dCID sCID token) (Plain flags pn frames)) mlen = do
    -- flag ... sCID
    headerBeg <- currentOffset wbuf
    (epn, epnLen) <- encodeLongHeaderPP conn wbuf InitialPacketType ver dCID sCID flags pn
    -- token
    encodeInt' wbuf $ fromIntegral $ B.length token
    copyByteString wbuf token
    -- length .. payload
    protectPayloadHeader conn wbuf frames pn epn epnLen headerBeg mlen InitialLevel

encodePlainPacket' conn wbuf (PlainPacket (RTT0 ver dCID sCID) (Plain flags pn frames)) mlen = do
    -- flag ... sCID
    headerBeg <- currentOffset wbuf
    (epn, epnLen) <- encodeLongHeaderPP conn wbuf RTT0PacketType ver dCID sCID flags pn
    -- length .. payload
    protectPayloadHeader conn wbuf frames pn epn epnLen headerBeg mlen RTT0Level

encodePlainPacket' conn wbuf (PlainPacket (Handshake ver dCID sCID) (Plain flags pn frames)) mlen = do
    -- flag ... sCID
    headerBeg <- currentOffset wbuf
    (epn, epnLen) <- encodeLongHeaderPP conn wbuf HandshakePacketType ver dCID sCID flags pn
    -- length .. payload
    protectPayloadHeader conn wbuf frames pn epn epnLen headerBeg mlen HandshakeLevel

encodePlainPacket' conn wbuf (PlainPacket (Short dCID) (Plain flags pn frames)) mlen = do
    -- flag
    let (epn, epnLen) = encodePacketNumber 0 {- dummy -} pn
        pp = encodePktNumLength epnLen
        Flags flags' = encodeShortHeaderFlags flags pp
    headerBeg <- currentOffset wbuf
    write8 wbuf flags'
    -- dCID
    let (dcid, _) = unpackCID dCID
    copyShortByteString wbuf dcid
    protectPayloadHeader conn wbuf frames pn epn epnLen headerBeg mlen RTT1Level

----------------------------------------------------------------

encodeLongHeader :: WriteBuffer
                 -> Version -> CID -> CID
                 -> IO ()
encodeLongHeader wbuf ver dCID sCID = do
    write32 wbuf $ encodeVersion ver
    let (dcid, dcidlen) = unpackCID dCID
    write8 wbuf dcidlen
    copyShortByteString wbuf dcid
    let (scid, scidlen) = unpackCID sCID
    write8 wbuf scidlen
    copyShortByteString wbuf scid

----------------------------------------------------------------

encodeLongHeaderPP :: Connection -> WriteBuffer
                   -> LongHeaderPacketType -> Version -> CID -> CID
                   -> Flags Raw
                   -> PacketNumber
                   -> IO (EncodedPacketNumber, Int)
encodeLongHeaderPP _conn wbuf pkttyp ver dCID sCID flags pn = do
    let el@(_, pnLen) = encodePacketNumber 0 {- dummy -} pn
        pp = encodePktNumLength pnLen
        Flags flags' = encodeLongHeaderFlags pkttyp flags pp
    write8 wbuf flags'
    encodeLongHeader wbuf ver dCID sCID
    return el

----------------------------------------------------------------

protectPayloadHeader :: Connection -> WriteBuffer -> [Frame] -> PacketNumber -> EncodedPacketNumber -> Int -> Buffer -> Maybe Int -> EncryptionLevel -> IO [ByteString]
protectPayloadHeader conn wbuf frames pn epn epnLen headerBeg mlen lvl = do
    secret <- getTxSecret conn lvl
    cipher <- getCipher conn lvl
    (plaintext0,siz) <- encodeFramesWithPadding (payloadBuffer conn) (payloadBufferSize conn) frames
    here <- currentOffset wbuf
    let taglen = tagLength cipher
        plaintext = case mlen of
                      Nothing -> B.take siz plaintext0
                      Just expectedSize ->
                          let headerSize = (here `minusPtr` headerBeg)
                                         + (if lvl /= RTT1Level then 2 else 0)
                                         + epnLen
                              plainSize = expectedSize - headerSize - taglen
                          in B.take plainSize plaintext0
    when (lvl /= RTT1Level) $ do
        let len = epnLen + B.length plaintext + taglen
        -- length: assuming 2byte length
        encodeInt'2 wbuf $ fromIntegral len
    pnBeg <- currentOffset wbuf
    if epnLen == 1 then
        write8  wbuf $ fromIntegral epn
      else if epnLen == 2 then
        write16 wbuf $ fromIntegral epn
      else if epnLen == 3 then
        write24 wbuf epn
      else
        write32 wbuf epn
    -- post process
    headerEnd <- currentOffset wbuf
    header <- extractByteString wbuf (negate (headerEnd `minusPtr` headerBeg))
    -- payload
    let ciphertext = encrypt cipher secret plaintext header pn
    -- protecting header
    protectHeader headerBeg pnBeg epnLen cipher secret ciphertext
    hdr <- toByteString wbuf
    return (hdr:ciphertext)

----------------------------------------------------------------

-- fixme
protectHeader :: Buffer -> Buffer -> Int -> Cipher -> Secret -> [CipherText] -> IO ()
protectHeader headerBeg pnBeg epnLen cipher secret ctxttag0 = do
    flags <- Flags <$> peek8 headerBeg 0
    let Flags proFlags = protectFlags flags (mask `B.index` 0)
    poke8 proFlags headerBeg 0
    shuffle 0
    when (epnLen >= 2) $ shuffle 1
    when (epnLen >= 3) $ shuffle 2
    when (epnLen == 4) $ shuffle 3
  where
    [ctxt0,tag0] = ctxttag0
    ctxt
      | epnLen == 1 = B.drop 3 ctxt0
      | epnLen == 2 = B.drop 2 ctxt0
      | epnLen == 3 = B.drop 1 ctxt0
      | otherwise   = ctxt0
    slen = sampleLength cipher
    clen = B.length ctxt
    -- We assume that clen (the size of ciphertext) is larger than
    -- or equal to sample length (16 bytes) in many cases.
    sample | clen >= slen = Sample $ B.take slen ctxt
           | otherwise    = Sample (ctxt `B.append` B.take (slen - clen) tag0)
    hpKey = headerProtectionKey cipher secret
    Mask mask = protectionMask cipher hpKey sample
    shuffle n = do
        p0 <- peek8 pnBeg n
        let pp0 = p0 `xor` (mask `B.index` (n + 1))
        poke8 pp0 pnBeg n

----------------------------------------------------------------

encrypt :: Cipher -> Secret -> PlainText -> ByteString -> PacketNumber
        -> [CipherText]
encrypt cipher secret plaintext header pn =
    encryptPayload cipher key nonce plaintext (AddDat header)
  where
    key    = aeadKey cipher secret
    iv     = initialVector cipher secret
    nonce  = makeNonce iv bytePN
    bytePN = bytestring64 (fromIntegral pn)
