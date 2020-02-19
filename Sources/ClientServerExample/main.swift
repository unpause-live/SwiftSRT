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
    conn = $0
    if !isServer {
        // have the client write some data
        print("Sending \(buf.readableBytes) bytes, it will appear as several buffers on the server.")
        conn?.write(buf)?.whenComplete { result in
            print("write result=\(result)")
        }
    } else {
        $0.getName()?.whenSuccess {
            print("got a connection from \($0)")
        }
    }
}

let recv: ConnectionDataCallback = { _, data in
    print("got some data \(data)")
}

let ended: ConnectionStateCallback = { _ in
    print("conn ended")
    conn = nil
}

if isServer {
    print("making a server")
    // Make a server
    let serverChannel = try SrtServerBootstrap(group: group)
        // Define backlog and enable SO_REUSEADDR options at the server level
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(SrtChannelOptions.minVersion, value: makeSrtVersion(1, 3, 0))
        .serverChannelOption(SrtChannelOptions.reuseAddr, value: true)
        // Handler Pipeline: handlers that are processing events from accepted Channels
        // To demonstrate that we can have several reusable handlers we start with a Swift-NIO default
        // handler that limits the speed at which we read from the client if we cannot keep up with the
        // processing through EchoHandler.
        // This is to protect the server from overload.
        .childChannelInitializer { channel in
            channel.pipeline.addHandler(BackPressureHandler()).flatMap { _ in
                channel.pipeline.addHandler(Connection(connected: connected, received: recv, ended: ended))
            }
        }
        // These options are applied to accepted Channels
        // Let Swift-NIO adjust the buffer size, based on actual trafic.
        .childChannelOption(SrtChannelOptions.maxBW, value: -1)
        //
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
        .channelOption(SrtChannelOptions.maxBW, value: -1)
        .channelOption(SrtChannelOptions.minVersion, value: makeSrtVersion(1, 3, 0))
        .channelOption(SrtChannelOptions.streamID, value: "client")
        .connect(host: host, port: port).wait()
    // Block until the client channel closes
    try clientChannel.closeFuture.wait()
}
