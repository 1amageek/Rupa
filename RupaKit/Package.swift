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
            name: "RupaCapabilities",
            targets: ["RupaCapabilities"]
        ),
        .library(
            name: "RupaGeometry",
            targets: ["RupaGeometry"]
        ),
        .library(
            name: "RupaProjectModel",
            targets: ["RupaProjectModel"]
        ),
        .library(
            name: "RupaEvaluation",
            targets: ["RupaEvaluation"]
        ),
        .library(
            name: "RupaCADIntegration",
            targets: ["RupaCADIntegration"]
        ),
        .library(
            name: "RupaProject",
            targets: ["RupaProject"]
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
        .executable(
            name: "rupa-performance-benchmark",
            targets: ["RupaPerformanceBenchmark"]
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
            name: "RupaCapabilities",
            dependencies: [
                "RupaCoreTypes",
            ]
        ),
        .target(
            name: "RupaGeometry",
            dependencies: [
                "RupaCoreTypes",
            ]
        ),
        .target(
            name: "RupaProjectModel",
            dependencies: [
                "RupaCoreTypes",
                "RupaGeometry",
            ]
        ),
        .target(
            name: "RupaEvaluation",
            dependencies: [
                "RupaCoreTypes",
                "RupaGeometry",
                "RupaProjectModel",
            ]
        ),
        .target(
            name: "RupaCADIntegration",
            dependencies: [
                "RupaEvaluation",
                "RupaGeometry",
                "RupaProjectModel",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .target(
            name: "RupaProject",
            dependencies: [
                "RupaCoreTypes",
                "RupaEvaluation",
                "RupaProjectModel",
            ]
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
                "RupaCapabilities",
            ]
        ),
        .target(
            name: "RupaManufacturing",
            dependencies: [
                "RupaDomainFoundation",
                "RupaAutomation",
                "RupaCore",
                .product(name: "SwiftCAD", package: "swift-CAD"),
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
                "RupaCapabilities",
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
        .executableTarget(
            name: "RupaPerformanceBenchmark",
            dependencies: [
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAutomation",
                "RupaCore",
                .product(name: "SwiftCAD", package: "swift-CAD"),
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
            name: "RupaCapabilitiesTests",
            dependencies: ["RupaCapabilities"]
        ),
        .testTarget(
            name: "RupaGeometryTests",
            dependencies: ["RupaGeometry"]
        ),
        .testTarget(
            name: "RupaProjectModelTests",
            dependencies: ["RupaProjectModel"]
        ),
        .testTarget(
            name: "RupaEvaluationTests",
            dependencies: ["RupaEvaluation"]
        ),
        .testTarget(
            name: "RupaCADIntegrationTests",
            dependencies: [
                "RupaCADIntegration",
                "RupaProjectModel",
                "RupaCore",
                "RupaEvaluation",
            ]
        ),
        .testTarget(
            name: "RupaProjectTests",
            dependencies: ["RupaProject"]
        ),
        .testTarget(
            name: "RupaAutomationTests",
            dependencies: ["RupaAutomation"]
        ),
        .testTarget(
            name: "RupaDomainFoundationTests",
            dependencies: [
                "RupaDomainFoundation",
                "RupaCapabilities",
                "RupaAutomation",
            ]
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
                "RupaCapabilities",
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
