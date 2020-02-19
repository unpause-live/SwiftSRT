### Swift wrapper for SRT (Secure Reliable Transport)

This repo tracks stable releases of SRT in the Haivision git repo (https://github.com/haivision/srt). Currently at 1.4.1.

This wrapper is based on [swift-nio](https://github.com/apple/swift-nio) and is used in the same way, except that you
must use an `SrtEventLoopGroup` instance instead of a typical `MultithreadedEventLoopGroup` because the SRT sockets live
in userspace and are therefore incompatible with a standard NIO event loop.

See Sources/ClientServerExample for a usage example.