import Foundation
import NIO
import CSRT

internal typealias ChannelInitializerCallback = (Channel) -> EventLoopFuture<Void>

public final class SrtServerBootstrap {
    private let group: EventLoopGroup
    private let childGroup: EventLoopGroup
    private var serverChannelInit: ChannelInitializerCallback?
    private var childChannelInit: ChannelInitializerCallback?
    internal var childChannelOptions: ChannelOptions.Storage
    internal var serverChannelOptions: ChannelOptions.Storage

    /// Create a `SrtServerBootstrap` for the `EventLoopGroup` `group`.
    ///
    /// - parameters:
    ///     - group: The `EventLoopGroup` to use for the `ServerSocketChannel`.
    public convenience init(group: EventLoopGroup) {
        self.init(group: group, childGroup: group)
    }

    /// Create a `SrtServerBootstrap`.
    ///
    /// - parameters:
    ///     - group: The `EventLoopGroup` to use for the `bind` of the `ServerSocketChannel` and to accept new `SocketChannel`s with.
    ///     - childGroup: The `EventLoopGroup` to run the accepted `SocketChannel`s on.
    public init(group: EventLoopGroup, childGroup: EventLoopGroup) {
        guard group is SrtEventLoopGroup && childGroup is SrtEventLoopGroup else {
            fatalError("SrtServerBootstrap currently only supports SrtEventLoop")
        }
        self.childChannelOptions = ChannelOptions.Storage()
        self.serverChannelOptions = ChannelOptions.Storage()
        self.group = group
        self.childGroup = childGroup
        self.serverChannelInit = nil
        self.childChannelInit = nil
    }

    public func serverChannelOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> Self {
        self.serverChannelOptions.append(key: option, value: value)
        return self
    }

    public func childChannelOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> Self {
        self.childChannelOptions.append(key: option, value: value)
        return self
    }

    /// Initialize the `ServerSocketChannel` with `initializer`. The most common task in initializer is to add
    /// `ChannelHandler`s to the `ChannelPipeline`.
    ///
    /// The `ServerSocketChannel` uses the accepted `Channel`s as inbound messages.
    ///
    /// - note: To set the initializer for the accepted `SocketChannel`s, look at `ServerBootstrap.childChannelInitializer`.
    ///
    /// - parameters:
    ///     - initializer: A closure that initializes the provided `Channel`.
    public func serverChannelInitializer(_ initializer: @escaping (Channel) -> EventLoopFuture<Void>) -> Self {
        self.serverChannelInit = initializer
        return self
    }

    /// Initialize the accepted `SocketChannel`s with `initializer`. The most common task in initializer is to add
    /// `ChannelHandler`s to the `ChannelPipeline`.
    ///
    /// - warning: The `initializer` will be invoked once for every accepted connection. Therefore it's usually the
    ///            right choice to instantiate stateful `ChannelHandler`s within the closure to make sure they are not
    ///            accidentally shared across `Channel`s. There are expert use-cases where stateful handler need to be
    ///            shared across `Channel`s in which case the user is responsible to synchronise the state access
    ///            appropriately.
    ///
    /// The accepted `Channel` will operate on `ByteBuffer` as inbound and `IOData` as outbound messages.
    ///
    /// - parameters:
    ///     - initializer: A closure that initializes the provided `Channel`.
    public func childChannelInitializer(_ initializer: @escaping (Channel) -> EventLoopFuture<Void>) -> Self {
        self.childChannelInit = initializer
        return self
    }

    /// Specifies a timeout to apply to a bind attempt. Currently unsupported.
    ///
    /// - parameters:
    ///     - timeout: The timeout that will apply to the bind attempt.
    public func bindTimeout(_ timeout: TimeAmount) -> Self {
        return self
    }

    /// Bind the `ServerSocketChannel` to `host` and `port`.
    ///
    /// - parameters:
    ///     - host: The host to bind on.
    ///     - port: The port to bind on.
    public func bind(host: String, port: Int) throws -> EventLoopFuture<Channel> {
        return try bind0 {
            return try SocketAddress.makeAddressResolvingHost(host, port: port, protocolFamily: 0)
        }
    }

    /// Bind the `ServerSocketChannel` to `address`.
    ///
    /// - parameters:
    ///     - address: The `SocketAddress` to bind on.
    public func bind(to address: SocketAddress) throws -> EventLoopFuture<Channel> {
        return try bind0 { address }
    }

    private func bind0(_ makeSocketAddress: @escaping () throws -> SocketAddress) throws -> EventLoopFuture<Channel> {
        guard let group = self.group as? SrtEventLoopGroup,
              let childGroup = self.childGroup as? SrtEventLoopGroup else {
            fatalError("SrtServerBootstrap currently only supports SrtEventLoop")
        }
        print("at bind")
        let channel = try SrtServerChannel(childInitializer: childChannelInit,
                                           eventLoop: group,
                                           childLoopGroup: childGroup)
        return group.next().submit {
            channel.bind(to: try makeSocketAddress(), promise: nil)
            // Because of the way Swift enforces integer overflows, we can't use the SRT_EPOLL_ET constant here
            _ = group.registerChannel(channel, -2147483648 | Int32(SRT_EPOLL_IN.rawValue |
                                                                   SRT_EPOLL_ERR.rawValue))
            return channel
        }
    }

}

public final class SrtClientBootstrap {
    private let group: EventLoopGroup
    private var channelInit: ChannelInitializerCallback?
    internal var channelOptions: ChannelOptions.Storage

    public init(group: EventLoopGroup) {
        guard group is SrtEventLoopGroup else {
            fatalError("SrtClientBootstrap currently only supports SrtEventLoop")
        }
        self.channelOptions = ChannelOptions.Storage()
        self.group = group
        self.channelInit = nil
    }

    public func channelInitializer(_ initializer: @escaping (Channel) -> EventLoopFuture<Void>) -> Self {
        self.channelInit = initializer
        return self
    }

    public func channelOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> Self {
        self.channelOptions.append(key: option, value: value)
        return self
    }

    public func connect(host: String, port: Int) throws -> EventLoopFuture<Channel> {
        return try connect0 {
            return try SocketAddress.makeAddressResolvingHost(host, port: port, protocolFamily: 0)
        }
    }

    public func connect(to address: SocketAddress) throws -> EventLoopFuture<Channel> {
        return try connect0 { address }
    }

    private func connect0(_ makeSocketAddress: @escaping () throws -> SocketAddress) throws
        -> EventLoopFuture<Channel> {
        guard let group = self.group as? SrtEventLoopGroup else {
            fatalError("SrtClientBootstrap currently only supports SrtEventLoop")
        }
        let channel = try SrtClientChannel(channelInit: self.channelInit, eventLoop: group)
        let events: Int32 = -2147483648 | Int32(SRT_EPOLL_IN.rawValue |
                                       SRT_EPOLL_OUT.rawValue |
                                       SRT_EPOLL_ERR.rawValue)
        return group.registerChannel(channel, events).flatMap { _ in
            group.submit {
                channel.connect(to: try makeSocketAddress(), promise: nil)
                return channel
            }
        }
    }
}
