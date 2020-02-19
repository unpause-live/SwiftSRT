import NIO
import CSRT
import Dispatch
import Foundation

public class SrtEventLoopGroup: EventLoop {

    public init() throws {
        self.epid = try checkError(srt_epoll_create())
        self.inQueueKey = DispatchSpecificKey()
        let uuid = UUID()
        self.loopID = uuid
        self.queue = DispatchQueue(label: "srt.\(uuid.uuidString)")
        self.pollQueue = DispatchQueue(label: "srt.poll.\(uuid.uuidString)")
        self.serverChannels = [:]
        self.childChannels = [:]
        self.queue.setSpecific(key: self.inQueueKey, value: self.loopID)
        self.poll()
    }

    deinit {
        do {
            _ = try submit { srt_epoll_release(self.epid) }.wait()
        } catch {}
    }

    public func next() -> EventLoop { self }

    public func shutdownGracefully(queue: DispatchQueue, _ callback: @escaping (Error?) -> Void) {
        // TODO: wait until fds drain
        self.running = false
        callback(nil)
    }

    public func makeIterator() -> EventLoopIterator { EventLoopIterator([self]) }

    public var inEventLoop: Bool { DispatchQueue.getSpecific(key: self.inQueueKey) == self.loopID }

    /// Submit a given task to be executed by the `EventLoop`
    public func execute(_ task: @escaping () -> Void) {
        self.queue.async {
            task()
        }
    }

    /// Submit a given task to be executed by the `EventLoop`.
    /// Once the execution is complete the returned `EventLoopFuture` is notified.
    ///
    /// - parameters:
    ///     - task: The closure that will be submitted to the `EventLoop` for execution.
    /// - returns: `EventLoopFuture` that is notified once the task was executed.
    public func submit<T>(_ task: @escaping () throws -> T) -> EventLoopFuture<T> {
        let promise = makePromise(of: T.self)
        if !inEventLoop {
            self.queue.async {
                do {
                    promise.succeed(try task())
                } catch {
                    promise.fail(error)
                }
            }
        } else {
            do {
                promise.succeed(try task())
            } catch {
                promise.fail(error)
            }
        }
        return promise.futureResult
    }

    public func submitOnPollQueue<T>(_ task: @escaping () throws -> T) -> EventLoopFuture<T> {
        let promise = makePromise(of: T.self)
        self.pollQueue.async {
            do {
                promise.succeed(try task())
            } catch {
                promise.fail(error)
            }
        }
        return promise.futureResult
    }

    /// Schedule a `task` that is executed by this `SelectableEventLoop` at the given time.
    @discardableResult
    public func scheduleTask<T>(deadline: NIODeadline, _ task: @escaping () throws -> T) -> Scheduled<T> {
        let deadline = DispatchTime(uptimeNanoseconds: deadline.uptimeNanoseconds)
        let promise = makePromise(of: T.self)
        self.queue.asyncAfter(deadline: deadline) {
            do {
                promise.succeed(try task())
            } catch {
                promise.fail(error)
            }
        }
        return Scheduled(promise: promise) {}
    }

    /// Schedule a `task` that is executed by this `SelectableEventLoop` after the given amount of time.
    @discardableResult
    public func scheduleTask<T>(in deadline: TimeAmount, _ task: @escaping () throws -> T) -> Scheduled<T> {
        let deadline: Double = Double(deadline.nanoseconds) / 1_000_000_000.0
        let promise = makePromise(of: T.self)
        self.queue.asyncAfter(deadline: .now() + deadline) {
            do {
                promise.succeed(try task())
            } catch {
                promise.fail(error)
            }
        }
        return Scheduled(promise: promise) {}
    }

    /// Checks that this call is run from the `EventLoop`. If this is called from within the `EventLoop` this function
    /// will have no effect, if called from outside the `EventLoop` it will crash the process with a trap.
    public func preconditionInEventLoop(file: StaticString, line: UInt) {
        dispatchPrecondition(condition: .onQueue(self.queue))
    }

    internal func registerChannel(_ channel: SrtChannel, _ events: Int32) -> EventLoopFuture<Int32> {
        let epid = self.epid
        return submitOnPollQueue { [weak self] in
            var events = events
            let result = try checkError(srt_epoll_add_usock(epid, channel.socket().descriptor, &events))
            if let channel = channel as? SrtClientChannel {
                self?.childChannels[channel.socket().descriptor] = Weak(value: channel)
            } else if let channel = channel as? SrtServerChannel {
                let descriptor = channel.socket().descriptor
                print("registering server channel with fd \(descriptor) self=\(self)")
                self?.serverChannels[descriptor] = Weak(value: channel)
                print("channel is \(self?.serverChannels[descriptor])")
            }
            return result
        }
    }

    internal func unregisterChannel(_ channel: SrtChannel) -> EventLoopFuture<Int32> {
        let epid = self.epid
        return submitOnPollQueue { [weak self] in
            let result = try checkError(srt_epoll_remove_usock(epid, channel.socket().descriptor))
            self?.childChannels.removeValue(forKey: channel.socket().descriptor)
            self?.serverChannels.removeValue(forKey: channel.socket().descriptor)
            return result
        }
    }

    private func poll() {
        guard running else { return }
        self.pollQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            var readfds = [Int32](repeating: 0, count: strongSelf.serverChannels.count + strongSelf.childChannels.count)
            var writefds = [Int32](repeating: 0, count: strongSelf.childChannels.count)
            var readfdlen = Int32(readfds.count)
            var writefdlen = Int32(writefds.count)
            srt_epoll_wait(strongSelf.epid, &readfds, &readfdlen, &writefds, &writefdlen, 100, nil, nil, nil, nil)
            for idx in 0..<Int(readfdlen) {
                let readfd = readfds[idx]
                strongSelf.serverChannels[readfd]?.value?.readTrigger()
                strongSelf.childChannels[readfd]?.value?.readTrigger()
            }
            for idx in 0..<Int(writefdlen) {
                let writefd = writefds[idx]
                strongSelf.childChannels[writefd]?.value?.writeTrigger()
            }
            
            strongSelf.poll()
        }
    }

    private let epid: Int32
    private let queue: DispatchQueue
    internal let pollQueue: DispatchQueue
    private let inQueueKey: DispatchSpecificKey<UUID>
    private let loopID: UUID
    private var childChannels: [Int32: Weak<SrtClientChannel>]
    private var serverChannels: [Int32: Weak<SrtServerChannel>]
    private var running = true
}

private class Weak<T: AnyObject> {
    public weak var value: T?
    public init (value: T) {
        self.value = value
    }
}
