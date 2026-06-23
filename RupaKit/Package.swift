// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "RupaKit",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "RupaKit",
            targets: ["RupaKit"]
        ),
        .library(
            name: "RupaCore",
            targets: ["RupaCore"]
        ),
        .library(
            name: "RupaUI",
            targets: ["RupaUI"]
        ),
        .library(
            name: "RupaRendering",
            targets: ["RupaRendering"]
        ),
        .library(
            name: "RupaPreview",
            targets: ["RupaPreview"]
        ),
        .library(
            name: "RupaAutomation",
            targets: ["RupaAutomation"]
        ),
        .library(
            name: "RupaAgent",
            targets: ["RupaAgent"]
        ),
        .library(
            name: "RupaCLIKit",
            targets: ["RupaCLIKit"]
        ),
        .executable(
            name: "rupa",
            targets: ["RupaCLI"]
        ),
    ],
    dependencies: [
        .package(name: "swift-CAD", path: "../swift-CAD"),
        .package(url: "https://github.com/1amageek/mac-component", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "RupaKit",
            dependencies: [
                "RupaCore",
                "RupaAutomation",
            ]
        ),
        .target(
            name: "RupaCore",
            dependencies: [
                .product(name: "SwiftCAD", package: "swift-CAD"),
                .product(name: "Collections", package: "swift-collections"),
            ]
        ),
        .target(
            name: "RupaUI",
            dependencies: [
                "RupaCore",
                "RupaAgent",
                "RupaRendering",
                "RupaPreview",
                .product(name: "MacComponent", package: "mac-component"),
            ]
        ),
        .target(
            name: "RupaRendering",
            dependencies: [
                "RupaCore",
            ]
        ),
        .target(
            name: "RupaPreview",
            dependencies: [
                "RupaCore",
            ]
        ),
        .target(
            name: "RupaAutomation",
            dependencies: [
                "RupaCore",
            ]
        ),
        .target(
            name: "RupaAgent",
            dependencies: [
                "RupaCore",
                "RupaAutomation",
            ]
        ),
        .target(
            name: "RupaCLIKit",
            dependencies: [
                "RupaCore",
                "RupaAutomation",
                "RupaAgent",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "RupaCLI",
            dependencies: [
                "RupaCLIKit",
            ]
        ),
        .testTarget(
            name: "RupaKitTests",
            dependencies: ["RupaKit"]
        ),
        .testTarget(
            name: "RupaCoreTests",
            dependencies: ["RupaCore"]
        ),
        .testTarget(
            name: "RupaAutomationTests",
            dependencies: ["RupaAutomation"]
        ),
        .testTarget(
            name: "RupaAgentTests",
            dependencies: ["RupaAgent"]
        ),
        .testTarget(
            name: "RupaUIPackageTests",
            dependencies: [
                "RupaAgent",
                "RupaUI",
            ]
        ),
        .testTarget(
            name: "RupaRenderingTests",
            dependencies: [
                "RupaCore",
                "RupaRendering",
            ]
        ),
        .testTarget(
            name: "RupaCLITests",
            dependencies: ["RupaCLIKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
