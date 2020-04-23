# quic-tls-work

Experiments and WIP based on projects:

- [tls](https://github.com/vincenthz/hs-tls) at commit `a2e831e2`

- [quic](https://github.com/kazu-yamamoto/quic) at commit `ccbc8b9a`

## Changes done

- Removed the QUIC extension from `ClientStatus` and `ServerStatus` and pass the
  value through a dedicated callback.  All the call does is set internal state
  with `setPeerParams` so this is safe to change.  The value is now set by a
  synchronous callback, so ahead of the previous MVar mechanism.

- Removed the secret info from `ClientStatus` and `ServerStatus` and pass this
  information through a callback.  Should be safe for the same reasons as
  previous change.

- TLS now has `stCryptLevel` to indicate what is the current encryption state in
  Tx/Rx directions.  When sending records, the QUIC record layer can annotate
  the record payload with the `CryptLevel`.  Doing this, it is now able to
  detect that pending content is for a different encryption level, so explicit
  flushing with `flushFlightIfNeeded` is not necessary anymore.  The normal TLS
  record layer continues to use non-annotated `ByteString` fragments, so the
  `RecordLayer` record is made polymorphic with an existential type.  The upside
  is that the polymorphic `bytes` type parameter prevents the library code from
  manipulating the content directly.  Values produced by `recordEncode(13)` have
  to go through `recordSendBytes` and nothing else.  On the `PacketFlightM`
  monad, this makes a rank 2 type parameter similar to ST monad.  The downside
  of the approach is that the added rigidity may block future experiments.  And
  the design is not always perfectly clean.  Some internal functions have a
  polymorphic result type, so need a `RecordLayer` argument.  But the functions
  also often need the `Context` argument for other purposes, like logging.  This
  adds repetition.

- For TLS 1.3 the calls `setTxState` and `setRxState` can infer the new
  encryption level from the secret type.  For versions before TLS 1.3 the
  encryption level is always `CryptMasterSecret` and set by `setMasterSecret`.

- Handshake fragments are now received through a synchronous `quicRecv` call
  instead of the `ClientContoller` and `ServerController` state machines.  The
  modification is safe because receiving is already reading from a message
  queue.  The `handshakeCheck` logic is not needed anymore.  `ClientNeedsMore`
  and `ServerNeedsMore` are removed, the existing Rx message parser detects
  incomplete parse and automatically calls `quicRecv` as many times as
  necessary.  `quicRecv` takes the current TLS encryption level to compare with
  the encryption level found by QUIC.

- Removing `handshakeCheck` required to move the control of TLS handshake
  previously executed by the Receiver thread to a different thread.  Otherwise
  the Receiver thread would hang when TLS messages are fragmented.  The Receiver
  is also the thread dispatching frames to the Crypto queue, and it would wait
  for itself.  A new thread is added for the duration of the last handshake
  steps, i.e. receiving client Finished (server) and receiving session tickets
  (client).

- The `quic` library had special logic to defer server processing of a Stream
  frame until connection is fully established.  This came from the fact that
  encryption level `RTT1Level` was set too early, when the server sends its
  flight, and before receiving the client flight at `Handshake` level.  But the
  variable `encryptionLevel` is used only by the Receiver, so it must map to the
  Rx encryption level.  Deferring the change to `RTT1Level` removes the need to
  handle Stream frames specially in the server side.  The global logic comparing
  incoming frames to the current level is enough.  One benefit now is that the
  logic can also apply to frames other than Stream.  For example a connection
  closure at `RTT1Level` will not be processed before the `Handshake` flight is
  processed.  This fully complies with the explanations in [RFC draft section
  5.7](https://tools.ietf.org/html/draft-ietf-quic-tls-27#section-5.7).

- In the Tx direction, handshake fragments are sent through `quicSend`.  This
  call takes a list of `ByteString` fragments annotated with encryption level.
  QUIC can wrap multiple frames together or not based on its own limits and
  fragmentation requirements.  Sending pushes to a queue, so moving everything
  to `quicSend` should be safe.  The data types `OutHndXXX` are all unified and
  replaced with `OutHandshake` generalization.  Except `OutEarlyData` which is
  kept as separate type, derived from the previous `OutHndClientHello`.  Early
  data does not go through TLS library but is generated by QUIC alone.

- The changes with `quicSend` and `quicRecv` removed `ClientNeedsMore` and
  `ServerNeedsMore` and the capability for QUIC to send necessary ACKs during
  handshake (commented as server "CI0" and client "three times rule").  To
  restore this we add an `IORef` and count how many `quicRecv` have been done
  since last `quicSend`.

- When testing the mapping between TLS and QUIC encryption levels in direction
  Rx, it was found the TLS server expected to receive records with the early
  traffic secret in 0-RTT handshakes.  Upon further inspection, the server logic
  in QUIC mode was actually skipping the pending action related to message
  EndOfEarlyData, however `setRxState` was left with `clientEarlySecret` instead
  of `clientHandshakeSecret`.  After fixing this, QUIC does not need encryption
  level `CryptEarlySecret` anymore, as one can expect.

- Package `quic` has requirements on `iproute` and `network-byte-order` that are
  not met by old Stackage LTS, so a lower version bound is added.

At this point the `ClientContoller` and `ServerController` state machines are
still executed but the all the actions that previously existed are done through
the new callbacks.  The dialog `ask`/`control` between TLS and QUIC only
verifies the end of the handshake.

## To do

- Understand how TLS handshake and threads terminate, try to remove the
  `ClientContoller` and `ServerController` state machines entirely.

- Understand error handling and make sure errors at any layer are reported
  appropriately.
  
- Understand how TLS alerts are managed.  Currently when a TLS error occurs,
  `tls` tries to send its alert but the QUIC record layer rejects with an
  exception.  Ideally error handling should not generate its own set of errors,
  as it tends to mask the original problem.

- See if it is possible to avoid repeting the TLS cipher in the `SecretInfo`
  data types.  Similarly, handshake mode and negotiated protocol could be
  available from the TLS context through API.

- Verify if `InpTransportError` with `NoError` always signals end of stream at
  `RTT1Level` like currently assumed.

- Verify if the new handshake ACK logic gives expected result.  Unclear if the
  frame should be sent before or after new receive.

- Verify if `quic` IORefs modified by the TLS to QUIC callbacks need atomic
  modify or not.

- Avoid Eq instances on secret info that take variable time.

- More generic interface to insert/extract some content in TLS extensions.
  Could be applicable to TLS < 1.3 as well.  And to all message types.

- See if a better design can be found for polymorphic `RecordLayer`, to avoid
  repetition with `Content` and `RecordLayer` arguments some functions need.
