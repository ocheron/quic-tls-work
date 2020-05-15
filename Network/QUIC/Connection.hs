module Network.QUIC.Connection (
    Connection
  , clientConnection
  , serverConnection
  , isClient
  , isServer
  -- * IO
  , closeSockets
  , connDebugLog
  , connQLog
  -- * Packet numbers
  , setPacketNumber
  , getPacketNumber
  , PeerPacketNumbers
  , emptyPeerPacketNumbers
  , getPeerPacketNumbers
  , addPeerPacketNumbers
  , clearPeerPacketNumbers
  , nullPeerPacketNumbers
  , fromPeerPacketNumbers
  -- * Crypto
  , getEncryptionLevel
  , setEncryptionLevel
  , checkEncryptionLevel
  , getPeerParameters
  , setPeerParameters
  , getCipher
  , getTLSMode
  , getTxSecret
  , getRxSecret
  , setInitialSecrets
  , getEarlySecretInfo
  , getHandshakeSecretInfo
  , getApplicationSecretInfo
  , setEarlySecretInfo
  , setHandshakeSecretInfo
  , setApplicationSecretInfo
  , dropSecrets
  -- * Migration
  , getMyCID
  , getMyCIDs
  , getMyCIDSeqNum
  , getPeerCID
  , isMyCID
  , myCIDsInclude
  , resetPeerCID
  , getNewMyCID
  , setMyCID
  , retirePeerCID
  , setPeerCIDAndRetireCIDs
  , retireMyCID
  , addPeerCID
  , choosePeerCID
  , setPeerStatelessResetToken
  , isStatelessRestTokenValid
  , checkResponse
  , validatePath
  -- * Misc
  , setVersion
  , getVersion
  , setThreadIds
  , addThreadIds
  , clearThreads
  , getSockInfo
  , setSockInfo
  , killHandshaker
  , setKillHandshaker
  , clearKillHandshaker
  -- * Transmit
  , keepPlainPacket
  , releasePlainPacket
  , releaseAllPlainPackets
  , releasePlainPacketRemoveAcks
  , getRetransmissions
  , MilliSeconds(..)
  -- * State
  , isConnectionOpen
  , isConnectionEstablished
  , isConnection1RTTReady
  , setConnection0RTTReady
  , setConnection1RTTReady
  , setConnectionEstablished
  , setCloseSent
  , setCloseReceived
  , isCloseSent
  , wait0RTTReady
  , wait1RTTReady
  , waitEstablished
  , waitClosed
  -- * Stream
  , getMyNewStreamId
  , getMyNewUniStreamId
  , getPeerStreamID
  , setPeerStreamID
  -- * StreamTable
  , putInputStream
  , putInputCrypto
  , insertStream
  , insertCryptoStreams
  , getCryptoOffset
  -- * Queue
  , takeInput
  , putInput
  , takeCrypto
  , putCrypto
  , takeOutput
  , tryPeekOutput
  , putOutput
  , putOutput'
  , putOutputPP
  -- * Role
  , setToken
  , getToken
  , getResumptionInfo
  , setRetried
  , getRetried
  , setResumptionSession
  , setNewToken
  , setRegister
  , getRegister
  , getUnregister
  , setTokenManager
  , getTokenManager
  , setMainThreadId
  , getMainThreadId
  , setCertificateChain
  , getCertificateChain
  -- Qlog
  , qlogReceived
  , qlogSent
  , qlogDropped
  , qlogRecvInitial
  , qlogSentRetry
  -- Types
  , headerBuffer
  , headerBufferSize
  , payloadBuffer
  , payloadBufferSize
  ) where

import Network.QUIC.Connection.Crypto
import Network.QUIC.Connection.Migration
import Network.QUIC.Connection.Misc
import Network.QUIC.Connection.PacketNumber
import Network.QUIC.Connection.Queue
import Network.QUIC.Connection.Role
import Network.QUIC.Connection.State
import Network.QUIC.Connection.Stream
import Network.QUIC.Connection.StreamTable
import Network.QUIC.Connection.Transmit
import Network.QUIC.Connection.Types
import Network.QUIC.Connection.Qlog
