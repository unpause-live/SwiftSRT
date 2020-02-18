import NIO
import SRT
import Foundation
import Dispatch

let host = "127.0.0.1"
let port = 1999
let group = try SrtEventLoopGroup()
let args = CommandLine.arguments
let isServer = !args.contains("-c")
var conn: Connection?

let allocator = ByteBufferAllocator()
let str = String(repeating: "Hello Friend", count: 250)
var buf = allocator.buffer(capacity: 4096)
buf.writeString(str)

let connected: ConnectionStateCallback = {
    print("got a connection")
    conn = $0
    if !isServer {
        // have the client write some data
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            conn?.write(buf)
        }
    }
}

let recv: ConnectionDataCallback = { conn, data in
    print("got some data")
}

let ended: ConnectionStateCallback = { conn in
    print("conn ended")
}

if isServer {
    print("making a server")
    // Make a server
    let serverChannel = try SrtServerBootstrap(group: group)
        // Define backlog and enable SO_REUSEADDR options at the server level
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        //.serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

        // .serverChannelInitializer { channel in
        //     print("\(channel) initialized")
        // }
        // Handler Pipeline: handlers that are processing events from accepted Channels
        // To demonstrate that we can have several reusable handlers we start with a Swift-NIO default
        // handler that limits the speed at which we read from the client if we cannot keep up with the
        // processing through EchoHandler.
        // This is to protect the server from overload.
        .childChannelInitializer { channel in
            print("in childChannelInitializer \(channel)")
            return channel.pipeline.addHandler(BackPressureHandler()).flatMap { _ in
                channel.pipeline.addHandler(Connection(connected: connected, received: recv, ended: ended))
            }
        }

        // Enable common socket options at the channel level (TCP_NODELAY and SO_REUSEADDR).
        // These options are applied to accepted Channels
        .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        // Message grouping
        .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
        // Let Swift-NIO adjust the buffer size, based on actual trafic.
        .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
        .bind(host: host, port: port).wait()
    // Block until the server channel closes
    try serverChannel.closeFuture.wait()
} else {
    print("making a client")
    // Make a client
    let clientChannel = try SrtClientBootstrap(group: group)
        .channelInitializer { channel in
            channel.pipeline.addHandler(BackPressureHandler()).flatMap { _ in
               channel.pipeline.addHandler(Connection(connected: connected, received: recv, ended: ended))
           }
        }
        .connect(host: host, port: port).wait()
    // Block until the client channel closes
    try clientChannel.closeFuture.wait()
}
