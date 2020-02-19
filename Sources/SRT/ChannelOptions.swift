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

public struct SrtChannelOptions {
    public static let maxBW = Types.SrtMaxBW()
    public static let passPhrase = Types.SrtPassphrase()
    public static let streamID = Types.SrtStreamID()
    public static let payloadSize = Types.SrtPayloadSize()
    public static let minVersion = Types.SrtMinVersion()
    public static let reuseAddr = Types.SrtReuseAddr()
}

public func makeSrtVersion(_ major: Int32, _ minor: Int32, _ patch: Int32) -> Int32 {
    (patch) + ((minor)*0x100) + ((major)*0x10000)
}

internal enum SrtOptionBinding {
    case pre
    case post
    case both
}

internal protocol SrtChannelOption: ChannelOption {
    var binding: SrtOptionBinding { get }
    var name: SRT_SOCKOPT { get }
}

// swiftlint:disable nesting
extension SrtChannelOptions {
    public enum Types {
        public struct SrtMaxBW: SrtChannelOption {
            public typealias Value = Int64
            internal var binding: SrtOptionBinding { .pre }
            internal var name: SRT_SOCKOPT { SRTO_MAXBW }
            public init() {}
        }

        public struct SrtPassphrase: SrtChannelOption {
            public typealias Value = String
            internal var binding: SrtOptionBinding { .pre }
            internal var name: SRT_SOCKOPT { SRTO_PASSPHRASE }
            public init() {}
        }

        public struct SrtStreamID: SrtChannelOption {
            public typealias Value = String
            internal var binding: SrtOptionBinding { .pre }
            internal var name: SRT_SOCKOPT { SRTO_STREAMID }
            public init() {}
        }

        public struct SrtPayloadSize: SrtChannelOption {
            public typealias Value = Int32
            internal var binding: SrtOptionBinding { .pre }
            internal var name: SRT_SOCKOPT { SRTO_PAYLOADSIZE }
            public init() {}
        }

        public struct SrtMinVersion: SrtChannelOption {
            public typealias Value = Int32
            internal var binding: SrtOptionBinding { .pre }
            internal var name: SRT_SOCKOPT { SRTO_MINVERSION }
            public init() {}
        }

        public struct SrtReuseAddr: SrtChannelOption {
            public typealias Value = Bool
            internal var binding: SrtOptionBinding { .pre }
            internal var name: SRT_SOCKOPT { SRTO_REUSEADDR }
            public init() {}
        }
    }
}
