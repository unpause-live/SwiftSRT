// swift-tools-version:5.1
/*
   SwiftSRT, Copyright 2020 Unpause SAS
   SRT, Copyright (c) 2018 Haivision Systems Inc.

   This Source Code Form is subject to the terms of the Mozilla Public
   License, v. 2.0. If a copy of the MPL was not distributed with this
   file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

import PackageDescription

let srtVersion = "\"1.4.1\""
let cOpts: [CSetting] = [.define("USE_OPENSSL"), .define("SRT_VERSION", to: srtVersion)]
let cxxOpts: [CXXSetting] = [.define("USE_OPENSSL"), .define("SRT_VERSION", to: srtVersion)]

let package = Package(
    name: "SwiftSRT",
    platforms: [
       .macOS(.v10_14),
       .iOS("13.1")
    ],
    products: [
        .library(
            name: "SRT",
            targets:["SwiftSRT"])
    ],
    dependencies: [.package(url: "https://github.com/apple/swift-nio.git", from: "2.9.0")],
    targets: [
        .systemLibrary(
            name: "OpenSSL",
            pkgConfig: "openssl",
            providers: [
                .apt(["openssl libssl-dev"]),
                .brew(["openssl"])
            ]
        ),
        .target(name: "CSRT",
                dependencies: ["OpenSSL"],
                cSettings: cOpts,
                cxxSettings: cxxOpts),
        .target(name: "SwiftSRT",
                dependencies: ["NIO", "CSRT"],
                cSettings: cOpts,
                cxxSettings: cxxOpts)
    ],
    swiftLanguageVersions: [.v5],
    cxxLanguageStandard: .cxx11
)
