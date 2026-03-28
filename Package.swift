// swift-tools-version: 5.9
// Package.swift
// MeloNX Air5 Edition
//
// Swift Package Manager manifest (for building/testing outside Xcode).

import PackageDescription

let package = Package(
    name: "MeloNX",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "MeloNXCore",
            targets: ["MeloNXCore"]
        )
    ],
    targets: [
        .target(
            name: "MeloNXCore",
            path: "Sources/MeloNX",
            exclude: [
                "MeloNXApp.swift",
                "UI",
                "Platform/Metal/Shaders.metal"
            ],
            swiftSettings: [
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "MeloNXTests",
            dependencies: ["MeloNXCore"],
            path: "Tests/MeloNXTests"
        )
    ]
)
