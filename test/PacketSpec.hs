{-# LANGUAGE OverloadedStrings #-}

module PacketSpec where

import Data.ByteString (ByteString)
import qualified Data.ByteString as B
import Data.IORef
import qualified Network.Socket as NS
import Test.Hspec

import Network.QUIC
import Network.QUIC.Internal

spec :: Spec
spec = do
    -- https://quicwg.org/base-drafts/draft-ietf-quic-tls.html#test-vectors-initial
    describe "test vector" $ do
        it "describes example of Client Initial draft 24" $ do
            let noLog _ = return ()
            let serverCID = makeCID $ dec16s "8394c8f03e515708"
                clientCID = makeCID ""
                -- dummy
                cls = return ()
            let clientConf = defaultClientConfig
                ver = head $ confVersions $ ccConfig clientConf
            s <- NS.socket NS.AF_INET NS.Stream NS.defaultProtocol
            q <- newRecvQ
            sref <- newIORef (s,q)
            clientConn <- clientConnection clientConf ver clientCID serverCID noLog noLog cls sref
            let serverConf = defaultServerConfig {
                    scKey   = "test/serverkey.pem"
                  , scCert  = "test/servercert.pem"
                  }
            serverConn <- serverConnection serverConf Draft24 serverCID clientCID (OCFirst serverCID) noLog noLog cls sref
            (PacketIC (CryptPacket header crypt), _) <- decodePacket clientInitialPacketBinary
            Just plain <- decryptCrypt serverConn crypt InitialLevel
            let ppkt = PlainPacket header plain
            clientInitialPacketBinary' <- B.concat <$> encodePlainPacket clientConn ppkt Nothing
            (PacketIC (CryptPacket header' crypt'), _) <- decodePacket clientInitialPacketBinary'
            Just plain' <- decryptCrypt serverConn crypt' InitialLevel
            header' `shouldBe` header
            plainFrames plain' `shouldBe` plainFrames plain

clientInitialPacketBinary :: ByteString
clientInitialPacketBinary = dec16 $ B.concat [
    "c0ff000017088394c8f03e5157080000449e3b343aa8535064a4268a0d9d7b1c"
  , "9d250ae355162276e9b1e3011ef6bbc0ab48ad5bcc2681e953857ca62becd752"
  , "4daac473e68d7405fbba4e9ee616c87038bdbe908c06d9605d9ac49030359eec"
  , "b1d05a14e117db8cede2bb09d0dbbfee271cb374d8f10abec82d0f59a1dee29f"
  , "e95638ed8dd41da07487468791b719c55c46968eb3b54680037102a28e53dc1d"
  , "12903db0af5821794b41c4a93357fa59ce69cfe7f6bdfa629eef78616447e1d6"
  , "11c4baf71bf33febcb03137c2c75d25317d3e13b684370f668411c0f00304b50"
  , "1c8fd422bd9b9ad81d643b20da89ca0525d24d2b142041cae0af205092e43008"
  , "0cd8559ea4c5c6e4fa3f66082b7d303e52ce0162baa958532b0bbc2bc785681f"
  , "cf37485dff6595e01e739c8ac9efba31b985d5f656cc092432d781db95221724"
  , "87641c4d3ab8ece01e39bc85b15436614775a98ba8fa12d46f9b35e2a55eb72d"
  , "7f85181a366663387ddc20551807e007673bd7e26bf9b29b5ab10a1ca87cbb7a"
  , "d97e99eb66959c2a9bc3cbde4707ff7720b110fa95354674e395812e47a0ae53"
  , "b464dcb2d1f345df360dc227270c750676f6724eb479f0d2fbb6124429990457"
  , "ac6c9167f40aab739998f38b9eccb24fd47c8410131bf65a52af841275d5b3d1"
  , "880b197df2b5dea3e6de56ebce3ffb6e9277a82082f8d9677a6767089b671ebd"
  , "244c214f0bde95c2beb02cd1172d58bdf39dce56ff68eb35ab39b49b4eac7c81"
  , "5ea60451d6e6ab82119118df02a586844a9ffe162ba006d0669ef57668cab38b"
  , "62f71a2523a084852cd1d079b3658dc2f3e87949b550bab3e177cfc49ed190df"
  , "f0630e43077c30de8f6ae081537f1e83da537da980afa668e7b7fb25301cf741"
  , "524be3c49884b42821f17552fbd1931a813017b6b6590a41ea18b6ba49cd48a4"
  , "40bd9a3346a7623fb4ba34a3ee571e3c731f35a7a3cf25b551a680fa68763507"
  , "b7fde3aaf023c50b9d22da6876ba337eb5e9dd9ec3daf970242b6c5aab3aa4b2"
  , "96ad8b9f6832f686ef70fa938b31b4e5ddd7364442d3ea72e73d668fb0937796"
  , "f462923a81a47e1cee7426ff6d9221269b5a62ec03d6ec94d12606cb485560ba"
  , "b574816009e96504249385bb61a819be04f62c2066214d8360a2022beb316240"
  , "b6c7d78bbe56c13082e0ca272661210abf020bf3b5783f1426436cf9ff418405"
  , "93a5d0638d32fc51c5c65ff291a3a7a52fd6775e623a4439cc08dd25582febc9"
  , "44ef92d8dbd329c91de3e9c9582e41f17f3d186f104ad3f90995116c682a2a14"
  , "a3b4b1f547c335f0be710fc9fc03e0e587b8cda31ce65b969878a4ad4283e6d5"
  , "b0373f43da86e9e0ffe1ae0fddd3516255bd74566f36a38703d5f34249ded1f6"
  , "6b3d9b45b9af2ccfefe984e13376b1b2c6404aa48c8026132343da3f3a33659e"
  , "c1b3e95080540b28b7f3fcd35fa5d843b579a84c089121a60d8c1754915c344e"
  , "eaf45a9bf27dc0c1e78416169122091313eb0e87555abd706626e557fc36a04f"
  , "cd191a58829104d6075c5594f627ca506bf181daec940f4a4f3af0074eee89da"
  , "acde6758312622d4fa675b39f728e062d2bee680d8f41a597c262648bb18bcfc"
  , "13c8b3d97b1a77b2ac3af745d61a34cc4709865bac824a94bb19058015e4e42d"
  , "c9be6c7803567321829dd85853396269"
  ]
