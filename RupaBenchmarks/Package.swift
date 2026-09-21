// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "RupaBenchmarks",
    platforms: [.macOS("27.0")],
    products: [
        .library(
            name: "RupaAgentCADBenchmarkJSONAdapter",
            targets: ["RupaAgentCADBenchmarkJSONAdapter"]
        ),
        .executable(
            name: "rupa-agent-cad-benchmark",
            targets: ["RupaAgentCADBenchmarkCLI"]
        ),
        .library(
            name: "RupaResponsivenessBaseline",
            targets: ["RupaResponsivenessBaseline"]
        ),
        .executable(
            name: "rupa-responsiveness-baseline",
            targets: ["RupaResponsivenessBaselineCLI"]
        ),
        .library(
            name: "RupaResponsivenessFixtureDocument",
            targets: ["RupaResponsivenessFixtureDocument"]
        ),
        .executable(
            name: "rupa-responsiveness-fixture-document",
            targets: ["RupaResponsivenessFixtureDocumentCLI"]
        ),
    ],
    dependencies: [
        .package(path: "../RupaKit"),
        .package(name: "swift-CAD", path: "../swift-CAD"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "RupaAgentCADBenchmarkJSONAdapter",
            dependencies: [
                .product(name: "RupaAgentCADBenchmark", package: "RupaKit"),
                .product(name: "RupaCoreTypes", package: "RupaKit"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .executableTarget(
            name: "RupaAgentCADBenchmarkCLI",
            dependencies: [
                .product(name: "RupaAgentCADBenchmark", package: "RupaKit"),
                "RupaAgentCADBenchmarkJSONAdapter",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaResponsivenessBaseline",
            dependencies: [
                .product(name: "RupaRendering", package: "RupaKit"),
                .product(name: "RupaViewportScene", package: "RupaKit"),
                .product(name: "RupaEvaluation", package: "RupaKit"),
                .product(name: "RupaGeometry", package: "RupaKit"),
                .product(name: "RupaProjectModel", package: "RupaKit"),
                .product(name: "RupaCoreTypes", package: "RupaKit"),
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .executableTarget(
            name: "RupaResponsivenessBaselineCLI",
            dependencies: [
                "RupaResponsivenessBaseline",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .testTarget(
            name: "RupaResponsivenessBaselineTests",
            dependencies: [
                "RupaResponsivenessBaseline",
            ]
        ),
        .target(
            name: "RupaResponsivenessFixtureDocument",
            dependencies: [
                "RupaResponsivenessBaseline",
                .product(name: "RupaCore", package: "RupaKit"),
                .product(name: "RupaCoreTypes", package: "RupaKit"),
                .product(name: "RupaGeometry", package: "RupaKit"),
                .product(name: "RupaProject", package: "RupaKit"),
                .product(name: "RupaProjectModel", package: "RupaKit"),
                .product(name: "RupaProjectPackage", package: "RupaKit"),
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .executableTarget(
            name: "RupaResponsivenessFixtureDocumentCLI",
            dependencies: [
                "RupaResponsivenessBaseline",
                "RupaResponsivenessFixtureDocument",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .testTarget(
            name: "RupaResponsivenessFixtureDocumentTests",
            dependencies: [
                "RupaResponsivenessBaseline",
                "RupaResponsivenessFixtureDocument",
                .product(name: "RupaCore", package: "RupaKit"),
                .product(name: "RupaProject", package: "RupaKit"),
                .product(name: "RupaProjectPackage", package: "RupaKit"),
            ]
        ),
        .testTarget(
            name: "RupaAgentCADBenchmarkJSONAdapterTests",
            dependencies: [
                "RupaAgentCADBenchmarkJSONAdapter",
                .product(name: "RupaAgentCADBenchmark", package: "RupaKit"),
            ]
        ),
        .testTarget(
            name: "RupaAgentCADBenchmarkCLITests",
            dependencies: [
                "RupaAgentCADBenchmarkCLI",
                "RupaAgentCADBenchmarkJSONAdapter",
                .product(name: "RupaAgentCADBenchmark", package: "RupaKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
