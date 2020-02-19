import NIO
import CSRT
import Foundation

internal final class SrtServerChannel {
    /// The `ByteBufferAllocator` for this `Channel`.
    public let allocator = ByteBufferAllocator()

    private var childChannelInit: ChannelInitializerCallback?

    /// An `EventLoopFuture` that will complete when this channel is finally closed.
    public var closeFuture: EventLoopFuture<Void> {
        return self.closePromise.futureResult
    }
    /// The parent `Channel` for this one, if any.
    public let parent: Channel? = nil

    /// The `EventLoop` this `Channel` belongs to.
    private let _eventLoop: SrtEventLoopGroup

    private var _pipeline: ChannelPipeline! = nil  // this is really a constant (set in .init) but needs `self` to be
                                                   // constructed and therefore a `var`. Do not change as this needs to 
                                                   // accessed from arbitrary threads.
    internal let closePromise: EventLoopPromise<Void>

    internal let serverSocket: SrtServerSocket

    /// The event loop group to use for child channels.
    private let childLoopGroup: SrtEventLoopGroup

    private var backlogSize: Int32 = 128

    internal init(childInitializer: ChannelInitializerCallback?,
                  eventLoop: SrtEventLoopGroup,
                  childLoopGroup: SrtEventLoopGroup) throws {
        self.childChannelInit = childInitializer
        self._eventLoop = eventLoop
        self.closePromise = eventLoop.makePromise()
        //self.connectionQueue = _eventLoop.channelQueue(label: "nio.transportservices.listenerchannel", qos: qos)
        self.childLoopGroup = childLoopGroup
        self.serverSocket = try SrtServerSocket()
        // Must come last, as it requires self to be completely initialized.
        self._pipeline = ChannelPipeline(channel: self)
    }
}

extension SrtServerChannel: ChannelOutboundInvoker {
    /// Write data into the `Channel`, automatically wrapping with `NIOAny`.
    ///
    /// - seealso: `ChannelOutboundInvoker.write`.
    public func write<T>(_ any: T) -> EventLoopFuture<Void> {
        return self.write(NIOAny(any))
    }

    /// Write data into the `Channel`, automatically wrapping with `NIOAny`.
    ///
    /// - seealso: `ChannelOutboundInvoker.write`.
    public func write<T>(_ any: T, promise: EventLoopPromise<Void>?) {
        self.write(NIOAny(any), promise: promise)
    }

    /// Write and flush data into the `Channel`, automatically wrapping with `NIOAny`.
    ///
    /// - seealso: `ChannelOutboundInvoker.writeAndFlush`.
    public func writeAndFlush<T>(_ any: T) -> EventLoopFuture<Void> {
        return self.writeAndFlush(NIOAny(any))
    }

    /// Write and flush data into the `Channel`, automatically wrapping with `NIOAny`.
    ///
    /// - seealso: `ChannelOutboundInvoker.writeAndFlush`.
    public func writeAndFlush<T>(_ any: T, promise: EventLoopPromise<Void>?) {
        self.writeAndFlush(NIOAny(any), promise: promise)
    }

    var eventLoop: EventLoop { _eventLoop }
}

extension SrtServerChannel: ChannelCore {
    /// Returns the local bound `SocketAddress`.
    func localAddress0() throws -> SocketAddress { try self.socket().localAddress() }

    /// Return the connected `SocketAddress`.
    func remoteAddress0() throws -> SocketAddress { throw ChannelError.operationUnsupported }

    /// Register with the `EventLoop` to receive I/O notifications.
    ///
    /// - parameters:
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    func register0(promise: EventLoopPromise<Void>?) {
        promise?.succeed(())
    }

    /// Register channel as already connected or bound socket.
    /// - parameters:
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    func registerAlreadyConfigured0(promise: EventLoopPromise<Void>?) {
        promise?.fail(ChannelError.operationUnsupported)
    }

    /// Bind to a `SocketAddress`.
    ///
    /// - parameters:
    ///     - to: The `SocketAddress` to which we should bind the `Channel`.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    func bind0(to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        self._eventLoop.submit { [weak self] in
            guard let strongSelf = self else { return }
            try strongSelf.serverSocket.bind(to: address)
            try strongSelf.serverSocket.listen(backlog: strongSelf.backlogSize)
        }.whenComplete { result in
            switch result {
            case .success: promise?.succeed(())
            case .failure(let err): promise?.fail(err)
            }
        }
    }
    /// Connect to a `SocketAddress`.
    ///
    /// - parameters:
    ///     - to: The `SocketAddress` to which we should connect the `Channel`.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    func connect0(to: SocketAddress, promise: EventLoopPromise<Void>?) {
        promise?.fail(ChannelError.operationUnsupported)
    }

    /// Write the given data to the outbound buffer.
    ///
    /// - parameters:
    ///     - data: The data to write, wrapped in a `NIOAny`.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    func write0(_ data: NIOAny, promise: EventLoopPromise<Void>?) {
        promise?.fail(ChannelError.operationUnsupported)
    }

    /// Try to flush out all previous written messages that are pending.
    func flush0() {

    }

    /// Request that the `Channel` perform a read when data is ready.
    func read0() {
    }

    /// Close the `Channel`.
    ///
    /// - parameters:
    ///     - error: The `Error` which will be used to fail any pending writes.
    ///     - mode: The `CloseMode` to apply.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    func close0(error: Error, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        do {
            try self.serverSocket.close()
            promise?.succeed(())
        } catch {
            promise?.fail(error)
        }
        self.closePromise.succeed(())
    }

    /// Trigger an outbound event.
    ///
    /// - parameters:
    ///     - event: The triggered event.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    func triggerUserOutboundEvent0(_ event: Any, promise: EventLoopPromise<Void>?) {

    }

    /// Called when data was read from the `Channel` but it was not consumed by any `ChannelInboundHandler` in the `ChannelPipeline`.
    ///
    /// - parameters:
    ///     - data: The data that was read, wrapped in a `NIOAny`.
    func channelRead0(_ data: NIOAny) {

    }

    /// Called when an inbound error was encountered but was not consumed by any `ChannelInboundHandler` in the `ChannelPipeline`.
    ///
    /// - parameters:
    ///     - error: The `Error` that was encountered.
    func errorCaught0(error: Error) {

    }
}

extension SrtServerChannel: SrtChannel {
    internal func socket() -> SrtBaseSocket { self.serverSocket }

    internal func readTrigger() {
        // accept
        do {
            let socket = try self.serverSocket.accept()
            let child = try SrtClientChannel(socket: socket, parent: self, eventLoop: self.childLoopGroup)
            // Because of the way Swift enforces integer overflows, we can't use the SRT_EPOLL_ET constant here
            let events: Int32 = -2147483648 | Int32(SRT_EPOLL_IN.rawValue |
                                       SRT_EPOLL_OUT.rawValue |
                                       SRT_EPOLL_ERR.rawValue)
            self.childLoopGroup.registerChannel(child, events)
            self.childChannelInit?(child)
            child.pipeline.fireChannelActive()
        } catch {
            self._pipeline.fireErrorCaught(error)
        }
    }

    internal func writeTrigger() {
        // do nothing
    }

    internal func errorTrigger() {

    }

    /// The `ChannelPipeline` for this `Channel`.
    public var pipeline: ChannelPipeline {
        return self._pipeline
    }

    /// The local address for this channel.
    public var localAddress: SocketAddress? { try? self.localAddress0() }

    /// The remote address for this channel.
    public var remoteAddress: SocketAddress? { try? self.remoteAddress0() }

    /// Whether this channel is currently writable.
    public var isWritable: Bool {
        // TODO: implement
        return true
    }

    // swiftlint:disable:next identifier_name
    public var _channelCore: ChannelCore {
        return self
    }

    public var isActive: Bool { true }

    public func setOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> EventLoopFuture<Void> {
        if _eventLoop.inEventLoop {
            let promise: EventLoopPromise<Void> = _eventLoop.makePromise()
            executeAndComplete(promise) { try setOption0(option: option, value: value) }
            return promise.futureResult
        } else {
            return _eventLoop.submit { try self.setOption0(option: option, value: value) }
        }
    }

    private func setOption0<Option: ChannelOption>(option: Option, value: Option.Value) throws {
        switch option {
        case let optionValue as ChannelOptions.Types.SocketOption:
            try self.serverSocket.setOption(level: optionValue.level, name: optionValue.name, value: value)
        case is ChannelOptions.Types.BacklogOption:
            guard let value = value as? Int32 else { return }
            self.backlogSize = value
        default: ()
        }
    }

    public func getOption<Option: ChannelOption>(_ option: Option) -> EventLoopFuture<Option.Value> {
        if _eventLoop.inEventLoop {
            let promise: EventLoopPromise<Option.Value> = _eventLoop.makePromise()
            executeAndComplete(promise) { try getOption0(option: option) }
            return promise.futureResult
        } else {
            return _eventLoop.submit { try self.getOption0(option: option) }
        }
    }

    func getOption0<Option: ChannelOption>(option: Option) throws -> Option.Value {
        switch option {
        case let optionValue as ChannelOptions.Types.SocketOption:
            return try self.serverSocket.getOption(level: optionValue.level, name: optionValue.name)
        case is ChannelOptions.Types.BacklogOption:
            // swiftlint:disable:next force_cast
            return self.backlogSize as! Option.Value
        default: throw ChannelError.operationUnsupported
        }
    }
}

func executeAndComplete<T>(_ promise: EventLoopPromise<T>?, _ body: () throws -> T) {
    do {
        let result = try body()
        promise?.succeed(result)
    } catch {
        promise?.fail(error)
    }
}
