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
            name: "RupaCoreTypes",
            targets: ["RupaCoreTypes"]
        ),
        .library(
            name: "RupaUI",
            targets: ["RupaUI"]
        ),
        .library(
            name: "RupaAgentUI",
            targets: ["RupaAgentUI"]
        ),
        .library(
            name: "RupaViewportScene",
            targets: ["RupaViewportScene"]
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
            name: "RupaDomainFoundation",
            targets: ["RupaDomainFoundation"]
        ),
        .library(
            name: "RupaManufacturing",
            targets: ["RupaManufacturing"]
        ),
        .library(
            name: "RupaAgentProtocol",
            targets: ["RupaAgentProtocol"]
        ),
        .library(
            name: "RupaAgentRuntime",
            targets: ["RupaAgentRuntime"]
        ),
        .library(
            name: "RupaAgentTransport",
            targets: ["RupaAgentTransport"]
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
                "RupaDomainFoundation",
            ]
        ),
        .target(
            name: "RupaCore",
            dependencies: [
                "RupaCoreTypes",
                .product(name: "SwiftCAD", package: "swift-CAD"),
                .product(name: "Collections", package: "swift-collections"),
            ]
        ),
        .target(
            name: "RupaCoreTypes",
            dependencies: []
        ),
        .target(
            name: "RupaUI",
            dependencies: [
                "RupaCore",
                "RupaDomainFoundation",
                "RupaRendering",
                "RupaPreview",
                .product(name: "MacComponent", package: "mac-component"),
            ]
        ),
        .target(
            name: "RupaAgentUI",
            dependencies: [
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaCore",
                "RupaDomainFoundation",
                "RupaUI",
            ]
        ),
        .target(
            name: "RupaRendering",
            dependencies: [
                "RupaCore",
                "RupaViewportScene",
            ]
        ),
        .target(
            name: "RupaViewportScene",
            dependencies: [
                "RupaCore",
                .product(name: "SwiftCAD", package: "swift-CAD"),
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
            name: "RupaDomainFoundation",
            dependencies: [
                "RupaCore",
                "RupaAutomation",
            ]
        ),
        .target(
            name: "RupaManufacturing",
            dependencies: [
                "RupaDomainFoundation",
                "RupaAutomation",
                "RupaCore",
            ]
        ),
        .target(
            name: "RupaAgent",
            dependencies: [
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
            ]
        ),
        .target(
            name: "RupaAgentProtocol",
            dependencies: [
                "RupaCore",
                "RupaAutomation",
                "RupaDomainFoundation",
            ]
        ),
        .target(
            name: "RupaAgentRuntime",
            dependencies: [
                "RupaCore",
                "RupaAutomation",
                "RupaDomainFoundation",
                "RupaAgentProtocol",
            ]
        ),
        .target(
            name: "RupaAgentTransport",
            dependencies: [
                "RupaCore",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
            ]
        ),
        .target(
            name: "RupaCLIKit",
            dependencies: [
                "RupaCore",
                "RupaAutomation",
                "RupaDomainFoundation",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "RupaCLI",
            dependencies: [
                "RupaCLIKit",
            ]
        ),
        .target(
            name: "RupaAgentTestFixtures",
            dependencies: [
                "RupaCore",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            path: "Tests/RupaAgentTestFixtures"
        ),
        .target(
            name: "RupaAgentIntegrationTestFixtures",
            dependencies: [
                "RupaAgent",
                "RupaAgentTransport",
                "RupaCore",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            path: "Tests/RupaAgentIntegrationTestFixtures"
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
            name: "RupaDomainFoundationTests",
            dependencies: ["RupaDomainFoundation"]
        ),
        .testTarget(
            name: "RupaManufacturingTests",
            dependencies: [
                "RupaManufacturing",
                "RupaDomainFoundation",
                "RupaCore",
            ]
        ),
        .testTarget(
            name: "RupaAgentTests",
            dependencies: [
                "RupaAgent",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaAgentTestFixtures",
                "RupaAgentIntegrationTestFixtures",
            ]
        ),
        .testTarget(
            name: "RupaAgentContractTests",
            dependencies: [
                "RupaAgent",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAutomation",
                "RupaDomainFoundation",
                "RupaCore",
                "RupaAgentTestFixtures",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "RupaAgentSurfaceTests",
            dependencies: [
                "RupaAgent",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAutomation",
                "RupaCore",
                "RupaAgentTestFixtures",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .testTarget(
            name: "RupaAgentSketchTests",
            dependencies: [
                "RupaAgent",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaAutomation",
                "RupaCore",
                "RupaAgentTestFixtures",
                "RupaAgentIntegrationTestFixtures",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .testTarget(
            name: "RupaAgentModelingTests",
            dependencies: [
                "RupaAgent",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaAutomation",
                "RupaCore",
                "RupaAgentTestFixtures",
                "RupaAgentIntegrationTestFixtures",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .testTarget(
            name: "RupaAgentSelectionTests",
            dependencies: [
                "RupaAgent",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaAutomation",
                "RupaCore",
                "RupaAgentTestFixtures",
                "RupaAgentIntegrationTestFixtures",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .testTarget(
            name: "RupaAgentInspectionTests",
            dependencies: [
                "RupaAgent",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaAutomation",
                "RupaCore",
                "RupaAgentTestFixtures",
                "RupaAgentIntegrationTestFixtures",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .testTarget(
            name: "RupaAgentTopologyPersistenceTests",
            dependencies: [
                "RupaAgent",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaAutomation",
                "RupaCore",
                "RupaAgentTestFixtures",
                "RupaAgentIntegrationTestFixtures",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .testTarget(
            name: "RupaAgentTransportTests",
            dependencies: [
                "RupaAgent",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
            ]
        ),
        .testTarget(
            name: "RupaUIPackageTests",
            dependencies: [
                "RupaAgentProtocol",
                "RupaAgentTransport",
                "RupaAgentUI",
                "RupaDomainFoundation",
                "RupaUI",
            ]
        ),
        .testTarget(
            name: "RupaRenderingTests",
            dependencies: [
                "RupaCore",
                "RupaRendering",
                "RupaViewportScene",
            ]
        ),
        .testTarget(
            name: "RupaCLITests",
            dependencies: [
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaCLIKit",
                "RupaDomainFoundation",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
