# quic-tls-work

Experiments and WIP based on projects:

- [tls](https://github.com/vincenthz/hs-tls) at commit `5ddf3e00`

- [quic](https://github.com/kazu-yamamoto/quic) at commit `2ddb37b3`

## Changes done

- Handshake secrets in QUIC are modified and used in threads that have no direct
  synchronization sometimes.  We now use atomic write with compare-and-swap in
  case some architectures have relaxed cache coherence or a data dependency with
  other variables is needed later.

- Generation of handshake ACKs with `HndState` counter is now aligned to the
  original implementation.  The code modifications counted ServerHello in the
  flight EncryptedExtensions..ServerFinished, but the packet numbering space is
  per encryption level.  Now the counter is reset when changing Rx level, so
  ServerHello is excluded from the count.  The ACK logic is generic and can be
  extended to other parts of the handshake easily.

- A new constructor `Error_Exception` is added to solve the complexity related
  to bidirectional interactions between QUIC and TLS for error handling.
  Previously all exceptions raised by a callback, whether for QUIC or the
  pre-existing hooks like `onCertificateRequest`, were converted to string with
  `Error_Misc`.  The client code was not able to signal error conditions with
  typed exceptions.  On the opposite, `Error_Exception` carries the exception in
  its original form with help of a `SomeException` existential.  The constructor
  is now used in some places inside TLS, although `Error_Misc` is still used
  conservatively for a number of known exceptions like `IOException` and avoid
  changing external behavior.  A QUIC client can use `Error_Exception` to signal
  through TLS "receive" code flow that a version retry is needed, reverting the
  workaround in commit `2ddb37b3`.  This is just an example and could be used
  more.

- While reviewing existing TLS code, some possible simplifications were found.
  The library tries to have more control over exceptions that are raised, so
  `throwCore` don't need a polymorphic exception argument.  Some uses of
  `MonadIO` were not needed after the change to `sendPacket`, and the same could
  be implemented for `recvPacket`.

## To do

- See if it is possible to avoid repeating the TLS cipher in the `SecretInfo`
  data types.  Similarly, handshake mode and negotiated protocol could be
  available from the TLS context through API.

- More generic interface to insert/extract some content in TLS extensions.
  Could be applicable to TLS < 1.3 as well.  And to all message types.
