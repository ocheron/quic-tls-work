module Network.QUIC.Utils where

import Data.ByteString (ByteString)
import Data.ByteString.Base16
import Data.ByteString.Short (ShortByteString)
import qualified Data.ByteString.Short as Short
import Data.Char (chr)

dec16 :: ByteString -> ByteString
dec16 = fst . decode

enc16 :: ByteString -> ByteString
enc16 = encode

dec16s :: ShortByteString -> ShortByteString
dec16s = Short.toShort . fst . decode . Short.fromShort

enc16s :: ShortByteString -> ShortByteString
enc16s = Short.toShort . encode . Short.fromShort

shortToString :: ShortByteString -> String
shortToString = map (chr . fromIntegral) . Short.unpack
