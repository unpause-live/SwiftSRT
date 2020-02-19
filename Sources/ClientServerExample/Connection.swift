import SRT
import NIO

typealias ConnectionStateCallback = (_ ctx: Connection) -> Void
typealias ConnectionDataCallback = (_ ctx: Connection, _ data: ByteBuffer) -> Void

final class Connection: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private let connected: ConnectionStateCallback
    private let received: ConnectionDataCallback
    private let ended: ConnectionStateCallback
    private weak var ctx: ChannelHandlerContext?

    public init(connected: @escaping ConnectionStateCallback,
                received: @escaping ConnectionDataCallback,
                ended: @escaping ConnectionStateCallback) {

        self.ended = ended
        self.received = received
        self.connected = connected
    }

    // Invoked on client connection
    public func channelRegistered(context: ChannelHandlerContext) { }

    public func channelActive(context: ChannelHandlerContext) {
        self.ctx = context
        self.connected(self)
    }

    // Invoked on client disconnect
    public func channelInactive(context: ChannelHandlerContext) {
        self.ended(self)
    }

    public func close() {
        if let ctx = self.ctx {
            ctx.pipeline.eventLoop.execute { ctx.close(promise: nil) }
        }
    }

    public func write(_ bytes: ByteBuffer) -> EventLoopFuture<Void>? {
        guard let ctx = self.ctx else { return nil }

        let promise = ctx.pipeline.eventLoop.makePromise(of: Void.self)
        ctx.pipeline.eventLoop.execute { [weak self] in
            guard let strongSelf = self else {
                return
            }
            let data = strongSelf.wrapOutboundOut(bytes)
            ctx.writeAndFlush(data, promise: promise)
        }
        return promise.futureResult
    }

    // Invoked when data are received from the client
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let bytes = self.unwrapInboundIn(data)
        self.received(self, bytes)
    }

    // Invoked when channelRead as processed all the read event in the current read operation
    public func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    // Invoked when an error occurs
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)
    }
}