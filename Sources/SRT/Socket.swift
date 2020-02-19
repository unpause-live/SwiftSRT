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

import Foundation
import NIO
import CSRT

typealias SrtSocketDescriptor = Int32

class SrtBaseSocket {

    internal class func makeSocket() throws -> SrtSocketDescriptor {
        try checkError(srt_create_socket())
    }

    internal init(descriptor: SrtSocketDescriptor, setNonBlocking: Bool) throws {
        self.descriptor = descriptor
        var yesVal: Bool = true
        _ = try checkError(srt_setsockflag(descriptor, SRTO_RCVSYN, &yesVal, Int32(MemoryLayout<Bool>.size)))
        _ = try checkError(srt_setsockflag(descriptor, SRTO_SNDSYN, &yesVal, Int32(MemoryLayout<Bool>.size)))
        if setNonBlocking {
            var noVal: Bool = false
            _ = try checkError(srt_setsockopt(descriptor, 0, SRTO_RCVSYN, &noVal, Int32(MemoryLayout<Bool>.size)))
            //_ = try checkError(srt_setsockopt(descriptor, 0, SRTO_SNDSYN, &noVal, Int32(MemoryLayout<Bool>.size)))
        }
    }

    var isOpen: Bool { true }

    func close() throws {
        _ = try checkError(srt_close(descriptor))
    }

    func bind(to address: SocketAddress) throws {
        _ = try address.withSockAddr {
            try checkError(srt_bind(descriptor, $0, Int32($1)))
        }
    }

    func localAddress() throws -> SocketAddress {
        try get_addr { _ = try checkError(srt_getsockname($0, $1, $2)) }
    }

    func remoteAddress() throws -> SocketAddress {
        try get_addr { _ = try checkError(srt_getpeername($0, $1, $2)) }
    }

    final func setOption<T>(level: Int32, name: Int32, value: T) throws {
        var value = value
        let size = Int32(MemoryLayout<T>.size)
        _ = try checkError(srt_setsockflag(descriptor, SRT_SOCKOPT(rawValue: UInt32(name)), &value, size))
    }

    func getOption<T>(level: Int32, name: Int32) throws -> T {
        var size = Int32(MemoryLayout<T>.size)
        let storage = UnsafeMutableRawBufferPointer.allocate(byteCount: MemoryLayout<T>.stride,
                                                     alignment: MemoryLayout<T>.alignment)
        // write zeroes into the memory as Linux's getsockopt doesn't zero them out
        storage.initializeMemory(as: UInt8.self, repeating: 0)
        var val = storage.bindMemory(to: T.self).baseAddress!
        // initialisation will be done by getsockopt
        defer {
            val.deinitialize(count: 1)
            storage.deallocate()
        }

        _ = try checkError(srt_getsockflag(descriptor, SRT_SOCKOPT(rawValue: UInt32(name)), val, &size))
        return val.pointee
    }

    typealias AddressBody = (Int32, UnsafeMutablePointer<sockaddr>, UnsafeMutablePointer<Int32>) throws -> Void
    private func get_addr(_ body: AddressBody) throws -> SocketAddress {
        var addr = sockaddr_storage()

        try addr.withMutableSockAddr { addressPtr, size in
             var size = Int32(size)
             try body(descriptor, addressPtr, &size)
        }
        return try addr.convert()
    }

    internal let descriptor: SrtSocketDescriptor
}

class SrtServerSocket: SrtBaseSocket {

    public final class func bootstrap(protocolFamily: Int32, host: String, port: Int) throws -> SrtServerSocket {
        let socket = try SrtServerSocket()
        try socket.bind(to: SocketAddress.makeAddressResolvingHost(host, port: port, protocolFamily: protocolFamily))
        try socket.listen()
        return socket
    }

    init(setNonBlocking: Bool = true) throws {
        let sock = try SrtBaseSocket.makeSocket()
        try super.init(descriptor: sock, setNonBlocking: setNonBlocking)
    }

    /// Start to listen for new connections.
    ///
    /// - parameters:
    ///     - backlog: The backlog to use.
    /// - throws: An `SrtError` if creation of the socket failed.
    func listen(backlog: Int32 = 128) throws {
        _ = try checkError(srt_listen(super.descriptor, backlog))
        print("Listening")
    }

    func accept(setNonBlocking: Bool = true) throws -> SrtSocket {
        var addr = sockaddr_storage()
        let descriptor: Int32 = try addr.withMutableSockAddr { addressPtr, size in
            var size = Int32(size)
            return try checkError(srt_accept(super.descriptor, addressPtr, &size))
        }
        return try SrtSocket(descriptor)
    }
}

class SrtSocket: SrtBaseSocket {

    init(_ descriptor: Int32, setNonBlocking: Bool = true) throws {
        try super.init(descriptor: descriptor, setNonBlocking: setNonBlocking)
    }

    init(setNonBlocking: Bool = true) throws {
        let sock = try SrtBaseSocket.makeSocket()
        try super.init(descriptor: sock, setNonBlocking: setNonBlocking)
    }

    func connect(to address: SocketAddress) throws -> Bool {
        try address.withSockAddr {
            try checkError(srt_connect(descriptor, $0, Int32($1)))
        } == 0
    }

    func write(pointer: UnsafeRawBufferPointer) throws -> IOResult<Int32> {
        do {
            return .processed(try checkError(srt_send(super.descriptor,
                                pointer.baseAddress?.bindMemory(to: Int8.self,
                                                                capacity: pointer.count),
                                Int32(pointer.count))))
        } catch SrtMajorError.tryAgain(let minor) {
            return .wouldBlock(minor)
        }
    }

    func read(pointer: UnsafeMutableRawBufferPointer) throws -> IOResult<Int32> {
        do {
            return .processed(try checkError(srt_recv(super.descriptor,
                                pointer.baseAddress?.bindMemory(to: Int8.self,
                                                                capacity: pointer.count),
                                Int32(pointer.count))))
        } catch SrtMajorError.tryAgain(let minor) {
            return .wouldBlock(minor)
        }
    }

    func ignoreSIGPIPE() throws {

    }
}

extension SocketAddress {
    // This function is mostly the same as the version in swift-nio, but it uses hints
    public static func makeAddressResolvingHost(_ host: String,
                                                port: Int,
                                                protocolFamily: Int32 = 0) throws -> SocketAddress {
        var info: UnsafeMutablePointer<addrinfo>?
        var hints = addrinfo()
        hints.ai_flags = AI_PASSIVE
        hints.ai_family = protocolFamily
        hints.ai_socktype = SOCK_DGRAM

        guard getaddrinfo(host, String(port), &hints, &info) == 0  else {
            throw SocketAddressError.unknown(host: host, port: port)
        }

        defer {
            if info != nil {
                freeaddrinfo(info)
            }
        }

        if let info = info {
            switch info.pointee.ai_family {
            case AF_INET:
                return info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ptr in
                    SocketAddress(ptr.pointee, host: host)
                }
            case AF_INET6:
                return info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { ptr in
                    SocketAddress(ptr.pointee, host: host)
                }
            default:
                throw SocketAddressError.unsupported
            }
        } else {
            /* this is odd, getaddrinfo returned NULL */
            throw SocketAddressError.unsupported
        }
    }
}

extension sockaddr_storage {
    /// Converts the `socketaddr_storage` to a `sockaddr_in`.
    ///
    /// This will crash if `ss_family` != AF_INET!
    mutating func convert() -> sockaddr_in {
        precondition(self.ss_family == AF_INET)
        return withUnsafePointer(to: &self) {
            $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee
            }
        }
    }

    /// Converts the `socketaddr_storage` to a `sockaddr_in6`.
    ///
    /// This will crash if `ss_family` != AF_INET6!
    mutating func convert() -> sockaddr_in6 {
        precondition(self.ss_family == AF_INET6)
        return withUnsafePointer(to: &self) {
            $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                $0.pointee
            }
        }
    }

    mutating func convert() throws -> SocketAddress {
        switch self.ss_family {
        case UInt8(AF_INET):
            var sockAddr: sockaddr_in = self.convert()
            return  SocketAddress(sockAddr, host: try sockAddr.addressDescription())
        case UInt8(AF_INET6):
            var sockAddr: sockaddr_in6 = self.convert()
            return SocketAddress(sockAddr, host: try sockAddr.addressDescription())
        default:
            fatalError("unknown sockaddr family \(self.ss_family)")
        }
    }

    mutating func withMutableSockAddr<R>(_ body: (UnsafeMutablePointer<sockaddr>, Int) throws -> R) rethrows -> R {
        return try withUnsafeMutableBytes(of: &self) { p in
            try body(p.baseAddress!.assumingMemoryBound(to: sockaddr.self), p.count)
        }
    }
}

extension sockaddr_in {
    mutating func addressDescription() throws -> String {
        return try withUnsafePointer(to: &self.sin_addr) { addrPtr in
            // this uses inet_ntop which is documented to only fail if family is not AF_INET or AF_INET6 (or ENOSPC)
            try descriptionForAddress(family: AF_INET, bytes: addrPtr, length: Int(INET_ADDRSTRLEN))
        }
    }
}

extension sockaddr_in6 {
    mutating func addressDescription() throws -> String {
        return try withUnsafePointer(to: &self.sin6_addr) { addrPtr in
            // this uses inet_ntop which is documented to only fail if family is not AF_INET or AF_INET6 (or ENOSPC)
            try descriptionForAddress(family: AF_INET6, bytes: addrPtr, length: Int(INET6_ADDRSTRLEN))
        }
    }
}

internal func descriptionForAddress(family: CInt, bytes: UnsafeRawPointer, length byteCount: Int) throws -> String {
    var addressBytes: [Int8] = Array(repeating: 0, count: byteCount)
    return addressBytes.withUnsafeMutableBufferPointer { (addressBytesPtr: inout UnsafeMutableBufferPointer<Int8>) -> String in
        inet_ntop(family, bytes, addressBytesPtr.baseAddress!, socklen_t(byteCount))
        return addressBytesPtr.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: byteCount) { addressBytesPtr -> String in
            String(cString: addressBytesPtr)
        }
    }
}
