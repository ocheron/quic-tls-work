# quic-tls-work

Experiments and WIP based on projects:

- [tls](https://github.com/vincenthz/hs-tls) at commit `3727b12b`

- [quic](https://github.com/kazu-yamamoto/quic) at commit `a32ac198`

## Changes done

- Handshake mode and negotiated protocol are now taken from the TLS context and
  removed from `ApplicationSecretInfo`.

## To do

- We could add a new `TLSError` constructor taking `SomeException` to hold a
  `QUICError` (or any other type the record layer wishes).  This would restore
  the possibility for QUIC to throw negotation failures from `quicRecv`.

- See if it is possible to avoid repeating the TLS cipher in the `SecretInfo`
  data types.

- More generic interface to insert/extract some content in TLS extensions.
  Could be applicable to TLS < 1.3 as well.  And to all message types.

- See if a better design can be found for polymorphic `RecordLayer`, to avoid
  repetition with `Content` and `RecordLayer` arguments some functions need.
