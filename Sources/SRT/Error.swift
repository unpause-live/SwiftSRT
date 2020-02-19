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

import CSRT

public enum SrtMinorError: Int32 {

    // SrtMajorError.setup
    case none =  0
    case timeout = 1
    case rejected = 2
    case noRes = 3
    case security = 4
    case badListenParams = 5

    // SrtMajorError.connection
    case connLost = 11
    case noConn = 12

    // SrtMajorError.systemRes
    case thread = 21
    case memory = 22

    // SrtMajorError.fileSystem
    case seekg = 31
    case read = 32
    case seekp = 33
    case write = 34

    // SrtMajorError.notSupported
    case isBound = 41
    case isConnected = 42
    case invalid = 43
    case sidInvalid = 44
    case isUnbound = 45
    case noListen = 46
    case isRendezVous = 47
    case isRendUnbound = 48
    case invalidMsgApi = 49
    case invalidBufferApi = 50
    case busy = 51
    case xSize = 52
    case eidInvalid = 53
    case eempty = 54

    // SrtMajorError.tryAgain
    case writeAvailable = 61
    case readAvailable = 62
    case xmTimeout = 63
    case congestion = 64
}

public enum SrtMajorError: Error {
    case unknown
    case setup(SrtMinorError)
    case connection(SrtMinorError)
    case systemRes(SrtMinorError)
    case fileSystem(SrtMinorError)
    case notSupported(SrtMinorError)
    case tryAgain(SrtMinorError)
    case peerError
}

internal func checkError(_ apiVal: Int32) throws -> Int32 {
    guard apiVal < 0 else { return apiVal }
    let error = srt_getlasterror(nil)
    let major = error / 1000
    let minor = error - (major * 1000)
    guard major != 0 else { return apiVal }
    let errorDict: [Int32: SrtMajorError] = [
        -1: .unknown,
        1: .setup(SrtMinorError(rawValue: minor) ?? .none),
        2: .connection(SrtMinorError(rawValue: minor+10) ?? .none),
        3: .systemRes(SrtMinorError(rawValue: minor+20) ?? .none),
        4: .fileSystem(SrtMinorError(rawValue: minor+30) ?? .none),
        5: .notSupported(SrtMinorError(rawValue: minor+40) ?? .none),
        6: .tryAgain(SrtMinorError(rawValue: minor+60) ?? .none),
        7: .peerError
    ]
    throw errorDict[major] ?? SrtMajorError.unknown
}
