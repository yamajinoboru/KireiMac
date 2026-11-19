// swift-tools-version: 6.0
//
// Package.swift
// KireiMac
//
// 役割: macOS ネイティブメンテナンスアプリ「KireiMac」の Swift Package マニフェスト。
// 存在意義: Xcode プロジェクトファイルに依存せず、再現性の高いビルド・テスト・.appバンドル生成を可能にする。

import PackageDescription

let package = Package(
    name: "KireiMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "KireiMac", targets: ["KireiMac"])
    ],
    targets: [
        .executableTarget(
            name: "KireiMac",
            path: "Sources/KireiMac",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "KireiMacTests",
            dependencies: ["KireiMac"],
            path: "Tests/KireiMacTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
