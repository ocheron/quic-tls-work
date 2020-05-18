# quic-tls-work

Experiments and WIP based on projects:

- [tls](https://github.com/vincenthz/hs-tls) at commit `3727b12b`

- [quic](https://github.com/kazu-yamamoto/quic) at commit `a32ac198`

## Changes done

- Handshake mode and negotiated protocol are now taken from the TLS context and
  removed from `ApplicationSecretInfo`.  When 0-RTT is not possible, handshake
  mode is `RTT0` but no early traffic secret is set.  QUIC should use this as
  signal that 0-RTT has not been accepted and that early data should be skipped.

- Parameter `sharedExtensions` is renamed `sharedHelloExtensions` and added to
  `ServerHello` message before TLS 1.3.

- Alert protocol between client and server is restored so that a failure during
  TLS handshake interrupts the connection attempt on both sides.

- `SendClientHello` is not emitted a second time after HelloRetryRequest so that
  early traffic secret is set just once.
