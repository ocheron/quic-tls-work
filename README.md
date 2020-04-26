# quic-tls-work

Experiments and WIP based on projects:

- [tls](https://github.com/vincenthz/hs-tls) at commit `5ddf3e00`

- [quic](https://github.com/kazu-yamamoto/quic) at commit `2ddb37b3`

## To do

- We could add a new `TLSError` constructor taking `SomeException` to hold a
  `QUICError` (or any other type the record layer wishes).  This would restore
  the possibility for QUIC to throw negotation failures from `quicRecv`.

- See if it is possible to avoid repeating the TLS cipher in the `SecretInfo`
  data types.  Similarly, handshake mode and negotiated protocol could be
  available from the TLS context through API.

- Verify if the new handshake ACK logic gives expected result.  Unclear if the
  frame should be sent before or after new receive.

- Verify if `quic` IORefs modified by the TLS to QUIC callbacks need atomic
  modify or not.

- More generic interface to insert/extract some content in TLS extensions.
  Could be applicable to TLS < 1.3 as well.  And to all message types.

- See if a better design can be found for polymorphic `RecordLayer`, to avoid
  repetition with `Content` and `RecordLayer` arguments some functions need.
