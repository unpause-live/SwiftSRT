/*
 * SwiftSRT
 * Copyright (c) 2020 Unpause SAS
 *
 * SRT - Secure, Reliable, Transport
 * Copyright (c) 2018 Haivision Systems Inc.
 * 
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 * 
 */

import NIO
import CSRT
import Foundation
import Dispatch

internal final class SrtClientChannel {
    /// The `ByteBufferAllocator` for this `Channel`.
    public let allocator = ByteBufferAllocator()
    public typealias InboundOut = ByteBuffer

    /// An `EventLoopFuture` that will complete when this channel is finally closed.
    public var closeFuture: EventLoopFuture<Void> {
        return self.closePromise.futureResult
    }

    /// The parent `Channel` for this one, if any.
    public var parent: Channel?

    private var channelInit: ChannelInitializerCallback?
    /// The `EventLoop` this `Channel` belongs to.
    private let _eventLoop: SrtEventLoopGroup

    private var _pipeline: ChannelPipeline! = nil  // this is really a constant (set in .init) but needs `self` to be
                                                   // constructed and therefore a `var`. Do not change as this needs to 
                                                   // accessed from arbitrary threads.
    internal let closePromise: EventLoopPromise<Void>

    private let _socket: SrtSocket

    private var _active: Bool = false

    private var _writable: Bool = false

    private let sendQueue: DispatchQueue

    private let openPromise: EventLoopPromise<Void>

    internal init(channelInit: ChannelInitializerCallback? = nil,
                  socket: SrtSocket? = nil,
                  parent: Channel? = nil,
                  eventLoop: SrtEventLoopGroup) throws {
        self.channelInit = channelInit
        self._eventLoop = eventLoop
        self.closePromise = eventLoop.makePromise()
        self.openPromise = eventLoop.makePromise()
        self.parent = parent
        self._socket = try socket ?? SrtSocket()
        self.sendQueue = DispatchQueue(label: "sendQueue.\(UUID().uuidString)")
        // Must come last, as it requires self to be completely initialized.
        self._pipeline = ChannelPipeline(channel: self)
    }
}

extension SrtClientChannel: ChannelOutboundInvoker {
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

extension SrtClientChannel: ChannelCore {
    /// Returns the local bound `SocketAddress`.
    func localAddress0() throws -> SocketAddress { try self.socket().localAddress() }

    /// Return the connected `SocketAddress`.
    func remoteAddress0() throws -> SocketAddress { try self.socket().remoteAddress() }

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
        promise?.fail(ChannelError.operationUnsupported)
    }
    /// Connect to a `SocketAddress`.
    ///
    /// - parameters:
    ///     - to: The `SocketAddress` to which we should connect the `Channel`.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    func connect0(to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        do {
            guard try self._socket.connect(to: address) else {
                promise?.fail(ChannelError.operationUnsupported)
                return
            }
            self.channelInit?(self).whenComplete { _ in
                self._pipeline.fireChannelActive()
                promise?.succeed(())
            }
        } catch {
            promise?.fail(error)
        }
    }

    /// Write the given data to the outbound buffer.
    ///
    /// - parameters:
    ///     - data: The data to write, wrapped in a `NIOAny`.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    func write0(_ data: NIOAny, promise: EventLoopPromise<Void>?) {
        if !self._writable {
            // plug the queue until the connection is writable
            self.sendQueue.async { [weak self] in
                do {
                    try self?.openPromise.futureResult.wait()
                } catch {}
            }
        }
        self.sendQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            var data = strongSelf.unwrapData(data, as: ByteBuffer.self)
            do {
                while data.readableBytes > 0 {
                    let data0 = data.getSlice(at: data.readerIndex, length: min(data.readableBytes, 1316))
                    let result = try data0?.withUnsafeReadableBytes {
                        try strongSelf._socket.write(pointer: $0)
                    }
                    if case .processed(let value) = result {
                        data.moveReaderIndex(forwardBy: Int(value))
                    }
                }
                promise?.succeed(())
            } catch {
                promise?.fail(error)
            }
        }
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
            try self._socket.close()
            promise?.succeed(())
        } catch {
            promise?.fail(error)
        }
        self._eventLoop.unregisterChannel(self).whenComplete { _ in
            self.closePromise.succeed(())
        }
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

extension SrtClientChannel: SrtChannel {
    internal func socket() -> SrtBaseSocket { self._socket }

    internal func readTrigger() {
        do {
            var result: IOResult<Int32>
            repeat {
                var buffer = self.allocator.buffer(capacity: 4096)
                result = try buffer.withUnsafeMutableWritableBytes {
                    try self._socket.read(pointer: $0)
                }
                switch result {
                case .wouldBlock:
                    self._pipeline.fireChannelReadComplete()
                    return
                case .processed(let value):
                    if value == 0 {
                        // eof
                        self._pipeline.fireChannelInactive()
                        return
                    } else {
                        buffer.moveWriterIndex(forwardBy: Int(value))
                        self._pipeline.fireChannelRead(NIOAny(buffer))
                    }
                }
            } while true
        } catch SrtMajorError.connection(let minor) {
            if minor == .connLost {
                self._pipeline.fireChannelInactive()
                _ = self._pipeline.close()
            }
        } catch {
            // Caught some other error - report it.
            self._pipeline.fireErrorCaught(error)
        }
    }

    internal func writeTrigger() {
        if self._active == false {
            self._active = true
            self._writable = true
            self.openPromise.succeed(())
        }
        self._pipeline.fireChannelWritabilityChanged()
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
        //return true
        _writable
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
        try self._socket.setOption(option: option, value: value)
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
         try self._socket.getOption(option: option)
    }
}
