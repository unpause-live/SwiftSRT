### Swift wrapper for SRT (Secure Reliable Transport)

This repo tracks stable releases of SRT in the Haivision git repo (https://github.com/haivision/srt). Currently at 1.4.1.

This wrapper is based on [swift-nio](https://github.com/apple/swift-nio) and is used in the same way, except that you
must use an `SrtEventLoopGroup` instance instead of a typical `MultithreadedEventLoopGroup` because the SRT sockets live
in userspace and are therefore incompatible with a standard NIO event loop.

See https://github.com/unpause-live/SwiftSRT/tree/master/Sources/ClientServerExample for a usage example.

Work done / to be done:
- [x] Linux compatibility
- [x] macOS compatibility
- [ ] iOS compatibility
- [ ] Android compatibility
- [x] Server accepts (IPv4)
- [x] Client calls out (IPv4)
- [x] "Live" mode
- [ ] "File" mode
- [ ] "Rendez-vous" connections
- [ ] Bandwidth statistics
- [ ] Encryption
- [ ] Bonding
- Options:
    - [x] MaxBW
    - [x] Passphrase
    - [x] Stream ID
    - [x] Payload Size
    - [x] Reuse Address
    - [ ] MSS
    - [ ] Packet Filter
    - [ ] PB Key Length
    - [ ] Peer Latency
    - [ ] Peer Idle Time
    - [ ] Peer Version
    - [ ] KM State
    - [ ] Recv Latency
    - [ ] Congestion
    - [ ] Send Buffer Size
    - [ ] Too Late Packet Drop
    - [ ] Enforced Encryption
