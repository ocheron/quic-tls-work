module Network.QUIC.Types (
    Bytes
  , SendMany
  , Receive
  , LogAction
  , Close
  , Direction(..)
  , module Network.QUIC.Types.Ack
  , module Network.QUIC.Types.CID
  , module Network.QUIC.Types.Error
  , module Network.QUIC.Types.Frame
  , module Network.QUIC.Types.Integer
  , module Network.QUIC.Types.Packet
  , module Network.QUIC.Types.Queue
  , module Network.QUIC.Types.Resumption
  , module Network.QUIC.Types.Stream
  , module Network.QUIC.Types.UserError
  ) where

import Network.QUIC.Imports
import Network.QUIC.Types.Ack
import Network.QUIC.Types.CID
import Network.QUIC.Types.Error
import Network.QUIC.Types.Frame
import Network.QUIC.Types.Integer
import Network.QUIC.Types.Packet
import Network.QUIC.Types.Queue
import Network.QUIC.Types.Resumption
import Network.QUIC.Types.Stream
import Network.QUIC.Types.UserError

type SendMany = [ByteString] -> IO ()
type Receive  = IO CryptPacket
type LogAction = String -> IO ()
type Close = IO ()
