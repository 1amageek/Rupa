// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "RupaKit",
    platforms: [
        .macOS("27.0"),
    ],
    products: [
        .library(name: "RupaAgentCADBenchmark", targets: ["RupaAgentCADBenchmark"]),
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
            name: "RupaProjectAccessPlatform",
            targets: ["RupaProjectAccessPlatform"]
        ),
        .library(
            name: "RupaProjectAccessComposition",
            targets: ["RupaProjectAccessComposition"]
        ),
        .library(
            name: "RupaCLIComposition",
            targets: ["RupaCLIComposition"]
        ),
        .library(
            name: "RupaMCP",
            targets: ["RupaMCP"]
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
            name: "RupaAutomation",
            targets: ["RupaAutomation"]
        ),
        .library(
            name: "RupaDomainFoundation",
            targets: ["RupaDomainFoundation"]
        ),
        .library(
            name: "RupaCADDomain",
            targets: ["RupaCADDomain"]
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
            name: "RupaCLIKit",
            targets: ["RupaCLIKit"]
        ),
    ],
    dependencies: [
        .package(name: "swift-CAD", path: "../swift-CAD"),
        .package(url: "https://github.com/1amageek/mac-component", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
        .package(url: "https://github.com/1amageek/swift-sdk", from: "0.13.0"),
    ],
    targets: [
        .target(
            name: "RupaAgentCADBenchmark",
            dependencies: [
                "RupaAgentRuntime",
                "RupaAgentProtocol",
                "RupaKit",
                "RupaCore",
                "RupaCoreTypes",
                "RupaGeometry",
                "RupaCADDomain",
                "RupaDomainFoundation",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md", "Aggregate/DESIGN.md", "Semantic/DESIGN.md"]
        ),
        .testTarget(
            name: "RupaAgentCADBenchmarkTests",
            dependencies: [
                "RupaAgentCADBenchmark",
                "RupaCADDomain",
                "RupaCore",
                "RupaDomainFoundation",
                "RupaKit",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            resources: [
                .process("Fixtures"),
            ]
        ),
        .executableTarget(
            name: "RupaPerformanceBenchmark",
            dependencies: [
                "RupaAutomation", "RupaCore",
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ]
        ),
        .executableTarget(
            name: "RupaGeometryBufferBenchmark",
            dependencies: ["RupaGeometry"]
        ),
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
            exclude: ["DESIGN.md", "GeometryExchange/DESIGN.md"]
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
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaCADIntegration",
            dependencies: [
                "RupaCoreTypes",
                "RupaEvaluation",
                "RupaGeometry",
                "RupaProjectModel",
                .product(name: "SwiftCAD", package: "swift-CAD"),
                .product(name: "CADCore", package: "swift-CAD"),
                .product(name: "CADIR", package: "swift-CAD"),
                .product(name: "CADModeling", package: "swift-CAD"),
                .product(name: "CADTopology", package: "swift-CAD"),
                .product(name: "HashTreeCollections", package: "swift-collections"),
            ],
            exclude: ["DESIGN.md"]
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
            name: "RupaProjectAccessPlatform",
            path: "Sources/RupaProjectAccessPlatform",
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaProjectAccessComposition",
            dependencies: [
                "RupaProjectAccess",
                "RupaProjectAccessPlatform",
                "RupaAgentProtocol",
                "RupaCoreTypes",
                "RupaAgentTransport",
            ],
            path: "Sources/RupaProjectAccessComposition",
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaUI",
            dependencies: [
                "RupaKit",
                "RupaCore",
                "RupaGeometry",
                "RupaDomainFoundation",
                "RupaProject",
                "RupaRendering",
                "RupaViewportScene",
                .product(name: "MacComponent", package: "mac-component"),
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md", "Modeling/DESIGN.md", "Outliner/DESIGN.md", "ViewportShadingPanel/DESIGN.md"]
        ),
        .target(
            name: "RupaAgentUI",
            dependencies: [
                "RupaAgentProtocol",
                "RupaAgentTransport",
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
            exclude: ["DESIGN.md"],
            resources: [
                .process("RealityViewport/Resources"),
            ]
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
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaAutomation",
            dependencies: [
                "RupaCore",
                "RupaCoreTypes",
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaDomainFoundation",
            dependencies: [
                "RupaCore",
                "RupaCoreTypes",
                "RupaAutomation",
                "RupaCapabilities",
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaCADDomain",
            dependencies: [
                "RupaDomainFoundation",
                "RupaAutomation",
                "RupaCore",
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaManufacturing",
            dependencies: [
                "RupaDomainFoundation",
                "RupaCore",
                .product(name: "SwiftCAD", package: "swift-CAD"),
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
            name: "RupaCLIKit",
            dependencies: [
                "RupaMCP",
                "RupaProjectAccess",
                "RupaCore",
                "RupaCoreTypes",
                "RupaAutomation",
                "RupaDomainFoundation",
                "RupaAgentProtocol",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftCAD", package: "swift-CAD"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaMCP",
            dependencies: [
                "RupaAgentProtocol",
                "RupaCoreTypes",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "RupaCLIComposition",
            dependencies: [
                "RupaCLIKit",
                "RupaProjectAccessComposition",
                "RupaProjectAccessPlatform",
            ],
            path: "Sources/RupaCLIComposition",
            exclude: ["DESIGN.md"]
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
                "RupaAutomation",
                "RupaCADIntegration",
                "RupaCore",
                "RupaDomainFoundation",
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
                "RupaAutomation",
                "RupaCore",
                "RupaEvaluation",
                "RupaGeometry",
                "RupaProject",
                "RupaProjectModel",
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
                "RupaCore",
            ]
        ),
        .testTarget(
            name: "RupaProjectAccessPlatformTests",
            dependencies: [
                "RupaProjectAccessPlatform",
                "RupaAgentTransport",
            ]
        ),
        .testTarget(
            name: "RupaProjectAccessCompositionTests",
            dependencies: [
                "RupaProjectAccessComposition",
                "RupaProjectAccess",
                "RupaProjectAccessPlatform",
                "RupaAgentProtocol",
                "RupaCoreTypes",
                "RupaCore",
                "RupaAgentTransport",
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
            name: "RupaCADDomainTests",
            dependencies: [
                "RupaCADDomain",
                "RupaDomainFoundation",
                "RupaAutomation",
                "RupaCore",
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
            name: "RupaAgentContractTests",
            dependencies: [
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
                "RupaCADDomain",
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
                "RupaCLIKit",
                "RupaProjectAccess",
                "RupaCore",
                "RupaCoreTypes",
                "RupaAutomation",
                "RupaDomainFoundation",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "RupaMCPTests",
            dependencies: [
                "RupaAgentProtocol",
                "RupaCoreTypes",
                "RupaMCP",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
