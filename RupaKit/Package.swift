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
            name: "RupaProjectPackage",
            targets: ["RupaProjectPackage"]
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
            name: "RupaProjectAccess",
            targets: ["RupaProjectAccess"]
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
            name: "RupaAgentCADBenchmark",
            targets: ["RupaAgentCADBenchmark"]
        ),
        .library(
            name: "RupaAgentCADBenchmarkJSONAdapter",
            targets: ["RupaAgentCADBenchmarkJSONAdapter"]
        ),
        .executable(
            name: "rupa-agent-cad-benchmark",
            targets: ["RupaAgentCADBenchmarkCLI"]
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
        .executable(
            name: "rupa-geometry-buffer-benchmark",
            targets: ["RupaGeometryBufferBenchmark"]
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
                "RupaCoreTypes",
                "RupaAutomation",
                "RupaDomainFoundation",
                "RupaCADIntegration",
                "RupaEvaluation",
                "RupaGeometry",
                "RupaProject",
                "RupaProjectModel",
                "RupaViewportScene",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaCore",
            dependencies: [
                "RupaCoreTypes",
                "RupaGeometry",
                "RupaProjectModel",
                .product(name: "SwiftCAD", package: "swift-CAD"),
                .product(name: "CADModeling", package: "swift-CAD"),
                .product(name: "CADTopology", package: "swift-CAD"),
                .product(name: "Collections", package: "swift-collections"),
            ],
            exclude: ["DESIGN.md"]
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
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaProjectModel",
            dependencies: [
                "RupaCoreTypes",
                "RupaGeometry",
            ]
        ),
        .target(
            name: "RupaProjectPackage",
            dependencies: [
                "RupaCoreTypes",
                "RupaGeometry",
                "RupaProjectModel",
            ],
            exclude: ["DESIGN.md"]
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
                "RupaCoreTypes",
                "RupaEvaluation",
                "RupaGeometry",
                "RupaProjectModel",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .target(
            name: "RupaProject",
            dependencies: [
                "RupaAutomation",
                "RupaCore",
                "RupaCoreTypes",
                "RupaEvaluation",
                "RupaProjectModel",
                "RupaProjectPackage",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaProjectAccess",
            dependencies: [
                "RupaAgentProtocol",
                "RupaCoreTypes",
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaUI",
            dependencies: [
                "RupaKit",
                "RupaCore",
                "RupaDomainFoundation",
                "RupaProject",
                "RupaRendering",
                "RupaPreview",
                "RupaViewportScene",
                .product(name: "MacComponent", package: "mac-component"),
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaAgentUI",
            dependencies: [
                "RupaKit",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaCore",
                "RupaDomainFoundation",
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaRendering",
            dependencies: [
                "RupaCore",
                "RupaCoreTypes",
                "RupaGeometry",
                "RupaProjectModel",
                "RupaViewportScene",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaViewportScene",
            dependencies: [
                "RupaCore",
                "RupaCoreTypes",
                "RupaEvaluation",
                "RupaGeometry",
                "RupaProjectModel",
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
                "RupaCoreTypes",
            ]
        ),
        .target(
            name: "RupaDomainFoundation",
            dependencies: [
                "RupaCore",
                "RupaCoreTypes",
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
                "RupaKit",
                "RupaGeometry",
                "RupaProjectModel",
                "RupaCoreTypes",
                "RupaCore",
                "RupaAutomation",
                "RupaDomainFoundation",
                "RupaCapabilities",
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaAgentRuntime",
            dependencies: [
                "RupaKit",
                "RupaCoreTypes",
                "RupaCore",
                "RupaGeometry",
                "RupaProjectModel",
                "RupaAutomation",
                "RupaDomainFoundation",
                "RupaCapabilities",
                "RupaAgentProtocol",
                "RupaProject",
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaAgentTransport",
            dependencies: [
                "RupaCoreTypes",
                "RupaAgentProtocol",
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaAgentCADBenchmark",
            dependencies: [
                "RupaAgentRuntime",
                "RupaAgentProtocol",
                "RupaAutomation",
                "RupaKit",
                "RupaProject",
                "RupaCore",
                "RupaCoreTypes",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md", "Aggregate/DESIGN.md"]
        ),
        .target(
            name: "RupaAgentCADBenchmarkJSONAdapter",
            dependencies: ["RupaAgentCADBenchmark", "RupaCoreTypes"],
            exclude: ["DESIGN.md"]
        ),
        .executableTarget(
            name: "RupaAgentCADBenchmarkCLI",
            dependencies: [
                "RupaAgentCADBenchmarkJSONAdapter",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["DESIGN.md"]
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
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md"]
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
                "RupaKit",
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAutomation",
                "RupaCore",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .executableTarget(
            name: "RupaGeometryBufferBenchmark",
            dependencies: [
                "RupaGeometry",
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
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaAutomation",
                "RupaCapabilities",
                "RupaCore",
                "RupaDomainFoundation",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            path: "Tests/RupaAgentIntegrationTestFixtures"
        ),
        .testTarget(
            name: "RupaKitTests",
            dependencies: [
                "RupaCADIntegration",
                "RupaCore",
                "RupaEvaluation",
                "RupaGeometry",
                "RupaKit",
                "RupaProject",
                "RupaProjectModel",
            ]
        ),
        .testTarget(
            name: "RupaCoreTests",
            dependencies: ["RupaCore", "RupaProjectModel"]
        ),
        .testTarget(
            name: "RupaCoreTypesTests",
            dependencies: ["RupaCoreTypes"]
        ),
        .testTarget(
            name: "RupaCapabilitiesTests",
            dependencies: ["RupaCapabilities"]
        ),
        .testTarget(
            name: "RupaGeometryTests",
            dependencies: ["RupaCoreTypes", "RupaGeometry"]
        ),
        .testTarget(
            name: "RupaProjectModelTests",
            dependencies: ["RupaProjectModel"]
        ),
        .testTarget(
            name: "RupaProjectPackageTests",
            dependencies: ["RupaProjectPackage"]
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
            dependencies: [
                "RupaCore",
                "RupaEvaluation",
                "RupaProject",
                "RupaProjectPackage",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .testTarget(
            name: "RupaProjectAccessTests",
            dependencies: [
                "RupaProjectAccess",
                "RupaAgentProtocol",
                "RupaCoreTypes",
            ]
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
                "RupaCoreTypes",
                "RupaGeometry",
                "RupaKit",
                "RupaProject",
                "RupaProjectModel",
                "RupaCapabilities",
                "RupaAgentTestFixtures",
                "RupaAgentIntegrationTestFixtures",
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
                "RupaAgentIntegrationTestFixtures",
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
                "RupaAgentIntegrationTestFixtures",
            ]
        ),
        .testTarget(
            name: "RupaUIPackageTests",
            dependencies: [
                "RupaAgentProtocol",
                "RupaAgentRuntime",
                "RupaAgentTransport",
                "RupaAgentUI",
                "RupaAutomation",
                "RupaCapabilities",
                "RupaCore",
                "RupaCoreTypes",
                "RupaDomainFoundation",
                "RupaEvaluation",
                "RupaGeometry",
                "RupaKit",
                "RupaProject",
                "RupaProjectModel",
                "RupaRendering",
                "RupaUI",
                "RupaViewportScene",
            ]
        ),
        .testTarget(
            name: "RupaRenderingTests",
            dependencies: [
                "RupaCore",
                "RupaKit",
                "RupaRendering",
                "RupaViewportScene",
            ]
        ),
        .testTarget(
            name: "RupaViewportSceneTests",
            dependencies: [
                "RupaCore",
                "RupaEvaluation",
                "RupaKit",
                "RupaProjectModel",
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
                "RupaAgentIntegrationTestFixtures",
            ]
        ),
        .testTarget(
            name: "RupaAgentCADBenchmarkTests",
            dependencies: [
                "RupaAgentCADBenchmark",
            ],
            resources: [
                .process("Fixtures"),
            ]
        ),
        .testTarget(
            name: "RupaAgentCADBenchmarkJSONAdapterTests",
            dependencies: [
                "RupaAgentCADBenchmarkJSONAdapter",
                "RupaAgentCADBenchmark",
            ]
        ),
        .testTarget(
            name: "RupaAgentCADBenchmarkCLITests",
            dependencies: [
                "RupaAgentCADBenchmarkCLI",
                "RupaAgentCADBenchmarkJSONAdapter",
                "RupaAgentCADBenchmark",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
