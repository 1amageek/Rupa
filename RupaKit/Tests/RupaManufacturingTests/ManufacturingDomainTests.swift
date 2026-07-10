import Foundation
import RupaCore
import RupaDomainFoundation
import RupaManufacturing
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func manufacturingDomainRegistryExposesPrintabilityCapability() throws {
    let registry = try ManufacturingDomain.registry()
    let descriptors = registry.sortedCapabilityDescriptors()

    #expect(descriptors.map(\.id) == [
        ManufacturingDomain.validatePrintabilityCapabilityID,
    ])

    let descriptor = try #require(descriptors.first)
    #expect(descriptor.namespace == ManufacturingDomain.namespace)
    #expect(descriptor.name == "Validate Printability")
    #expect(!descriptor.mutatesDocument)
    #expect(descriptor.effect == .query)
    #expect(descriptor.resultKind == .validationReport)
    #expect(descriptor.resultFidelity == .sampledApproximation)
    #expect(descriptor.supportsDryRun)
    #expect(descriptor.targetKinds == ["document"])
    #expect(descriptor.parameters.map(\.id) == [
        "processID",
        "buildWidth",
        "buildDepth",
        "buildHeight",
        "requireMaterialAssignment",
        "requireExportReadyMesh",
        "overhangLimit",
        "minimumWallThickness",
        "minimumClearance",
    ])
    #expect(descriptor.parameters.first { $0.id == "buildWidth" }?.kind == .length)
    #expect(descriptor.parameters.first { $0.id == "overhangLimit" }?.kind == .angle)
    #expect(descriptor.parameters.first { $0.id == "processID" }?.choices.map(\.value) == [
        ManufacturingProcessID.materialExtrusion.rawValue,
        ManufacturingProcessID.powderBedFusion.rawValue,
        ManufacturingProcessID.vatPhotopolymerization.rawValue,
    ])
}

@Test(.timeLimit(.minutes(1)))
func manufacturingDomainUsesInjectedProcessCatalogForDiscoveryAndExecution() throws {
    let profile = ManufacturingProcessProfile(
        id: "additive.customFixture",
        name: "Custom Fixture",
        summary: "Fixture process with angle-limited support.",
        family: .materialExtrusion,
        supportStrategy: .overhangLimited
    )
    let catalog = try ManufacturingProcessCatalogSnapshot(
        defaultProcessID: profile.id,
        profiles: [profile]
    )
    let registry = try ManufacturingDomain.registry(processCatalog: catalog)
    let descriptor = try #require(
        registry.capabilityDescriptor(for: ManufacturingDomain.validatePrintabilityCapabilityID)
    )
    let processParameter = try #require(
        descriptor.parameters.first { $0.id == "processID" }
    )

    #expect(processParameter.defaultValue == .string(profile.id.rawValue))
    #expect(processParameter.choices.map(\.value) == [profile.id.rawValue])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityExecutesPayloadBuiltFromCapabilityContract() throws {
    let registry = try ManufacturingDomain.registry()
    let descriptor = try #require(
        registry.capabilityDescriptor(for: ManufacturingDomain.validatePrintabilityCapabilityID)
    )
    let session = try printableBoxSession(
        name: "Schema Printable",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.02
    )
    var values = DomainCommandPayloadBuilder().defaultValues(for: descriptor)
    values["buildWidth"] = .number(0.1)
    values["buildDepth"] = .number(0.1)
    values["buildHeight"] = .number(0.1)
    values["requireMaterialAssignment"] = .bool(false)
    let payload = try DomainCommandPayloadBuilder().payload(
        for: descriptor,
        values: values
    )

    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: descriptor.id,
            namespace: descriptor.namespace,
            payload: payload,
            expectedGeneration: session.generation
        ),
        in: session
    )

    #expect(result.message == "Manufacturing printability validation passed.")
    #expect(try stringValue(for: "outcome", in: result) == "passed")
    let process = try objectValue(for: "process", in: result)
    #expect(try stringValue(for: "id", in: process) == ManufacturingProcessID.materialExtrusion.rawValue)
    #expect(try stringValue(for: "family", in: process) == ManufacturingProcessFamily.materialExtrusion.rawValue)
    #expect(!result.didMutate)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityRejectsUnregisteredProcessBeforeAnalysis() throws {
    let registry = try ManufacturingDomain.registry()
    let session = EditorSession(document: .empty(named: "Unknown Process"))
    var caught: ManufacturingProcessCatalogError?

    do {
        _ = try DomainCommandExecutor(registry: registry).execute(
            DomainCommandRequest(
                capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
                namespace: ManufacturingDomain.namespace,
                payload: .object([
                    "processID": .string("additive.unknown"),
                ]),
                expectedGeneration: session.generation
            ),
            in: session
        )
    } catch let error as ManufacturingProcessCatalogError {
        caught = error
    }

    #expect(caught?.code == .unsupportedProcess)
    #expect(session.generation == DocumentGeneration(0))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPowderBedProcessReportsUnimplementedPowderEscapeAnalysis() throws {
    let registry = try ManufacturingDomain.registry()
    let session = try printableBoxSession(
        name: "Powder Printable",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.02
    )
    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([
                "processID": .string(ManufacturingProcessID.powderBedFusion.rawValue),
                "requireMaterialAssignment": .bool(false),
            ]),
            expectedGeneration: session.generation
        ),
        in: session
    )

    #expect(try stringValue(for: "outcome", in: result) == "unsupported")
    #expect(result.diagnostics.contains { $0.message.contains("trapped-powder") })
}

@Test(.timeLimit(.minutes(1)))
func manufacturingCapabilityLedgerEntryKeepsPrintabilityIncomplete() throws {
    let ledger = CapabilityLedgerService().ledger(
        additionalEntries: ManufacturingCapabilityLedgerProvider.entries()
    )
    let entry = try #require(
        ledger.entry(id: ManufacturingDomain.validatePrintabilityCapabilityID.rawValue)
    )

    #expect(entry.category == .domainModule)
    #expect(entry.currentRating == .partial)
    #expect(entry.blockingGateAssessments.map(\.gate).contains(.selectionTopology))
    #expect(entry.blockingGateAssessments.map(\.gate).contains(.inspectorAffordance))
    #expect(entry.blockingGateAssessments.map(\.gate).contains(.performanceBudget))
    #expect(entry.openWork.contains("Persist the build frame and project process, machine, and material settings as manufacturing semantic source."))
    #expect(entry.openWork.contains("Introduce spatial acceleration and enforce dense-mesh time, memory, cancellation, and copy budgets."))
    #expect(entry.nextRequiredResult.contains("persist project process, machine, material, and build-frame source"))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityReportsMissingGeneratedBodiesWithoutMutation() throws {
    let registry = try ManufacturingDomain.registry()
    let session = EditorSession(document: .empty(named: "Printable"))
    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([:])
        ),
        in: session
    )

    #expect(result.capabilityID == ManufacturingDomain.validatePrintabilityCapabilityID)
    #expect(result.namespace == ManufacturingDomain.namespace)
    #expect(result.generation == DocumentGeneration(0))
    #expect(!result.didMutate)
    #expect(!result.dryRun)
    #expect(result.automationResults.isEmpty)
    #expect(result.message == "Manufacturing printability validation failed.")
    #expect(result.diagnostics.contains { $0.severity == .error })
    #expect(result.diagnostics.contains { $0.message.contains("at least one generated body mesh") })
    #expect(try stringValue(for: "outcome", in: result) == "failed")
    #expect(try numberValue(for: "bodyCount", in: result) == 0.0)
    #expect(session.document.cadDocument.metadata.name == "Printable")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityPassesGeneratedBodyWithinBuildVolume() throws {
    let registry = try ManufacturingDomain.registry()
    let session = try printableBoxSession(
        name: "Pass Printable",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.02
    )
    let generation = session.generation
    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([
                "buildVolume": .object([
                    "widthMeters": .number(0.1),
                    "depthMeters": .number(0.1),
                    "heightMeters": .number(0.1),
                ]),
                "requireMaterialAssignment": .bool(false),
            ])
        ),
        in: session
    )

    #expect(result.generation == generation)
    #expect(!result.didMutate)
    #expect(result.automationResults.isEmpty)
    #expect(result.message == "Manufacturing printability validation passed.")
    #expect(try stringValue(for: "outcome", in: result) == "passed")
    #expect((try numberValue(for: "bodyCount", in: result)) > 0.0)
    #expect((try numberValue(for: "triangleCount", in: result)) > 0.0)
    let meshAnalysis = try objectValue(for: "meshAnalysis", in: result)
    #expect((try numberValue(for: "exportReadyBodyCount", in: meshAnalysis)) > 0.0)
    #expect(try numberValue(for: "totalOverhangAreaSquareMeters", in: meshAnalysis) == 0.0)
    #expect(result.diagnostics.allSatisfy { $0.severity == .info })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityFailsWhenGeneratedBodyExceedsBuildVolume() throws {
    let registry = try ManufacturingDomain.registry()
    let session = try printableBoxSession(
        name: "Oversize Printable",
        widthMeters: 0.3,
        heightMeters: 0.3,
        depthMeters: 0.3
    )
    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([
                "buildVolume": .object([
                    "widthMeters": .number(0.1),
                    "depthMeters": .number(0.1),
                    "heightMeters": .number(0.1),
                ]),
                "requireMaterialAssignment": .bool(false),
            ])
        ),
        in: session
    )

    #expect(!result.didMutate)
    #expect(result.message == "Manufacturing printability validation failed.")
    #expect(try stringValue(for: "outcome", in: result) == "failed")
    #expect(result.diagnostics.contains { $0.message.contains("exceed") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityFailsWhenRequiredMaterialAssignmentIsMissing() throws {
    let registry = try ManufacturingDomain.registry()
    let session = try printableBoxSession(
        name: "Material Printable",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.02
    )
    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([
                "buildVolume": .object([
                    "widthMeters": .number(0.1),
                    "depthMeters": .number(0.1),
                    "heightMeters": .number(0.1),
                ]),
            ])
        ),
        in: session
    )

    #expect(!result.didMutate)
    #expect(result.message == "Manufacturing printability validation failed.")
    #expect(try stringValue(for: "outcome", in: result) == "failed")
    #expect(result.diagnostics.contains { $0.severity == .error })
    #expect(result.diagnostics.contains { $0.message.contains("no material assignment") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityAndExportPreflightAcceptAssignedMaterial() throws {
    let registry = try ManufacturingDomain.registry()
    let session = try printableBoxSession(
        name: "Material Assigned Printable",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.02
    )
    let material = Material(
        name: "PETG",
        baseColor: ColorRGBA(r: 0.1, g: 0.5, b: 0.8, a: 1.0),
        metallic: 0.0,
        roughness: 0.45,
        opacity: 1.0
    )
    var metadata = session.document.productMetadata
    metadata.materialLibrary = MaterialLibrary(
        materials: [material.id: material],
        defaultMaterialID: material.id
    )
    _ = try session.execute(.replaceProductMetadata(metadata))
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try bodySceneNodeID(
        for: bodyFeatureID,
        in: session
    )
    _ = try session.execute(
        .setSceneNodeMaterial(id: bodySceneNodeID, materialID: material.id)
    )

    let validationResult = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([
                "buildVolume": .object([
                    "widthMeters": .number(0.1),
                    "depthMeters": .number(0.1),
                    "heightMeters": .number(0.1),
                ]),
            ])
        ),
        in: session
    )

    #expect(validationResult.message == "Manufacturing printability validation passed.")
    #expect(try stringValue(for: "outcome", in: validationResult) == "passed")
    #expect(validationResult.diagnostics.contains { $0.message.contains("All generated body meshes have material assignments.") })
    #expect(!validationResult.diagnostics.contains { $0.message.contains("no material assignment") })

    let exportService = DocumentExportService(
        preflightValidators: [
            ManufacturingExportPreflightValidator(
                options: ManufacturingPrintabilityOptions(
                    buildVolume: ManufacturingPrintabilityOptions.BuildVolume(
                        widthMeters: 0.1,
                        depthMeters: 0.1,
                        heightMeters: 0.1
                    )
                )
            ),
        ]
    )
    let exportResult = try exportService.export(
        document: session.document,
        generation: session.generation,
        to: temporaryExportURL(pathExtension: "3mf"),
        dryRun: true
    )

    #expect(exportResult.dryRun)
    #expect(exportResult.format == .threeMF)
    #expect(exportResult.diagnostics.contains { $0.message.contains("Manufacturing export gate for 3MF") })
    #expect(exportResult.diagnostics.allSatisfy { $0.severity != .error })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityAcceptsCompleteFaceMaterialCoverage() throws {
    let registry = try ManufacturingDomain.registry()
    let session = try printableBoxSession(
        name: "Face Material Printable",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.02
    )
    let material = Material(
        name: "PETG",
        baseColor: ColorRGBA(r: 0.1, g: 0.5, b: 0.8, a: 1.0),
        metallic: 0.0,
        roughness: 0.45,
        opacity: 1.0
    )
    var metadata = session.document.productMetadata
    metadata.materialLibrary = MaterialLibrary(
        materials: [material.id: material],
        defaultMaterialID: material.id
    )
    _ = try session.execute(.replaceProductMetadata(metadata))

    let topology = try TopologySnapshotService().snapshot(
        document: session.document,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )
    let faceTargets = topology.entries
        .filter { $0.kind == .face }
        .compactMap { $0.selectionTarget() }
    #expect(faceTargets.count > 1)
    for target in faceTargets {
        _ = try session.execute(
            .setTopologyMaterialBinding(
                target: target,
                materialID: material.id,
                process: TopologyMaterialBinding.Process(
                    namespace: "manufacturing",
                    processID: ManufacturingProcessID.materialExtrusion.rawValue
                )
            )
        )
    }

    let validationResult = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([
                "buildVolume": .object([
                    "widthMeters": .number(0.1),
                    "depthMeters": .number(0.1),
                    "heightMeters": .number(0.1),
                ]),
            ])
        ),
        in: session
    )

    #expect(validationResult.message == "Manufacturing printability validation passed.")
    #expect(try stringValue(for: "outcome", in: validationResult) == "passed")
    #expect(validationResult.diagnostics.contains { $0.message.contains("All generated body meshes have material assignments.") })
    #expect(!validationResult.diagnostics.contains { $0.message.contains("no material assignment") })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityRejectsConflictingFaceProcessOverride() throws {
    let registry = try ManufacturingDomain.registry()
    let session = try printableBoxSession(
        name: "Process Conflict Printable",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.02
    )
    let topology = try TopologySnapshotService().snapshot(
        document: session.document,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )
    let faceTarget = try #require(
        topology.entries.first { $0.kind == .face }?.selectionTarget()
    )
    _ = try session.execute(
        .setTopologyMaterialBinding(
            target: faceTarget,
            materialID: nil,
            process: TopologyMaterialBinding.Process(
                namespace: ManufacturingDomain.namespace.rawValue,
                processID: ManufacturingProcessID.vatPhotopolymerization.rawValue
            )
        )
    )

    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([
                "processID": .string(ManufacturingProcessID.materialExtrusion.rawValue),
                "requireMaterialAssignment": .bool(false),
            ]),
            expectedGeneration: session.generation
        ),
        in: session
    )

    #expect(try stringValue(for: "outcome", in: result) == "failed")
    #expect(result.diagnostics.contains { $0.message.contains("process overrides conflict") })
    let checks = try arrayValue(for: "checks", in: result)
    let processCheck = try #require(checks.compactMap(objectValue).first {
        $0["id"] == .string("manufacturing.processAssignment")
    })
    let references = try arrayValue(for: "references", in: processCheck)
    #expect(!references.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityFailsThinWallsBelowMinimum() throws {
    let registry = try ManufacturingDomain.registry()
    let session = try printableBoxSession(
        name: "Thin Wall Printable",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.0004
    )
    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([
                "buildVolume": .object([
                    "widthMeters": .number(0.1),
                    "depthMeters": .number(0.1),
                    "heightMeters": .number(0.1),
                ]),
                "requireMaterialAssignment": .bool(false),
                "minimumWallThicknessMeters": .number(0.0008),
            ])
        ),
        in: session
    )

    #expect(!result.didMutate)
    #expect(result.message == "Manufacturing printability validation failed.")
    #expect(try stringValue(for: "outcome", in: result) == "failed")
    #expect(result.diagnostics.contains { $0.message.contains("wall-thickness") })
    let meshAnalysis = try objectValue(for: "meshAnalysis", in: result)
    #expect((try numberValue(for: "minimumWallThicknessMeters", in: meshAnalysis)) < 0.0008)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityFailsBodiesBelowMinimumClearance() throws {
    let registry = try ManufacturingDomain.registry()
    let session = try closeBodiesSession(name: "Close Body Printable")
    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([
                "buildVolume": .object([
                    "widthMeters": .number(0.1),
                    "depthMeters": .number(0.1),
                    "heightMeters": .number(0.1),
                ]),
                "requireMaterialAssignment": .bool(false),
                "minimumClearanceMeters": .number(0.0002),
            ])
        ),
        in: session
    )

    #expect(!result.didMutate)
    #expect(result.message == "Manufacturing printability validation failed.")
    #expect(try stringValue(for: "outcome", in: result) == "failed")
    #expect(result.diagnostics.contains { $0.message.contains("clearance") })
    let meshAnalysis = try objectValue(for: "meshAnalysis", in: result)
    #expect((try numberValue(for: "minimumBodyClearanceMeters", in: meshAnalysis)) < 0.0002)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityFailsSheetMeshesForExportReadiness() throws {
    let registry = try ManufacturingDomain.registry()
    let session = try sheetSession(name: "Sheet Printable")
    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .object([
                "buildVolume": .object([
                    "widthMeters": .number(0.1),
                    "depthMeters": .number(0.1),
                    "heightMeters": .number(0.1),
                ]),
                "requireMaterialAssignment": .bool(false),
            ])
        ),
        in: session
    )

    #expect(!result.didMutate)
    #expect(result.message == "Manufacturing printability validation failed.")
    #expect(result.diagnostics.contains { $0.message.contains("export readiness") })
    #expect(try stringValue(for: "outcome", in: result) == "failed")
    let meshAnalysis = try objectValue(for: "meshAnalysis", in: result)
    #expect(try numberValue(for: "exportReadyBodyCount", in: meshAnalysis) == 0.0)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingExportPreflightRejectsThinWallSTL3MFAndSTEPDryRuns() throws {
    let session = try printableBoxSession(
        name: "Thin Wall Export",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.0004
    )
    let exportService = DocumentExportService(
        preflightValidators: [
            ManufacturingExportPreflightValidator(
                options: ManufacturingPrintabilityOptions(
                    buildVolume: ManufacturingPrintabilityOptions.BuildVolume(
                        widthMeters: 0.1,
                        depthMeters: 0.1,
                        heightMeters: 0.1
                    ),
                    requireMaterialAssignment: false,
                    minimumWallThicknessMeters: 0.0008,
                    minimumClearanceMeters: nil
                )
            ),
        ]
    )

    for pathExtension in ["stl", "3mf", "step"] {
        var caught: EditorError?

        do {
            _ = try exportService.export(
                document: session.document,
                generation: session.generation,
                to: temporaryExportURL(pathExtension: pathExtension),
                dryRun: true
            )
        } catch let error as EditorError {
            caught = error
        }

        let error = try #require(caught)
        #expect(error.code == .exportFailed)
        #expect(error.message.contains("Export preflight failed"))
        #expect(error.message.contains("wall-thickness"))
    }

    #expect(session.generation == DocumentGeneration(1))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingExportPreflightPassesPrintableSTLDryRunWithDiagnostics() throws {
    let session = try printableBoxSession(
        name: "Printable Export",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.02
    )
    let exportService = DocumentExportService(
        preflightValidators: [
            ManufacturingExportPreflightValidator(
                options: ManufacturingPrintabilityOptions(
                    buildVolume: ManufacturingPrintabilityOptions.BuildVolume(
                        widthMeters: 0.1,
                        depthMeters: 0.1,
                        heightMeters: 0.1
                    ),
                    requireMaterialAssignment: false
                )
            ),
        ]
    )

    let result = try exportService.export(
        document: session.document,
        generation: session.generation,
        to: temporaryExportURL(pathExtension: "stl"),
        dryRun: true
    )

    #expect(result.dryRun)
    #expect(result.format == .stl)
    #expect(result.byteCount == 0)
    #expect(result.generation == session.generation)
    #expect(result.diagnostics.contains { $0.message.contains("Manufacturing export gate for STL") })
    #expect(result.diagnostics.allSatisfy { $0.severity != .error })
    #expect(!result.validationFindings.isEmpty)
    #expect(result.validationFindings.allSatisfy { $0.outcome == .passed })
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingExportPreflightBlocksUnsupportedRequiredRule() throws {
    let session = try printableBoxSession(
        name: "Unsupported Powder Export",
        widthMeters: 0.02,
        heightMeters: 0.02,
        depthMeters: 0.02
    )
    let exportService = DocumentExportService(
        preflightValidators: [
            ManufacturingExportPreflightValidator(
                options: ManufacturingPrintabilityOptions(
                    processID: .powderBedFusion,
                    buildVolume: ManufacturingPrintabilityOptions.BuildVolume(
                        widthMeters: 0.1,
                        depthMeters: 0.1,
                        heightMeters: 0.1
                    ),
                    requireMaterialAssignment: false
                )
            ),
        ]
    )
    var caught: EditorError?

    do {
        _ = try exportService.export(
            document: session.document,
            generation: session.generation,
            to: temporaryExportURL(pathExtension: "stl"),
            dryRun: true
        )
    } catch let error as EditorError {
        caught = error
    }

    let error = try #require(caught)
    #expect(error.code == .exportFailed)
    #expect(error.message.contains("manufacturing.supportability"))
    #expect(error.message.contains("unsupported"))
    #expect(error.message.contains("trapped-powder"))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityDryRunRemainsNonMutating() throws {
    let registry = try ManufacturingDomain.registry()
    let session = EditorSession(document: .empty(named: "Dry Printable"))
    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
            namespace: ManufacturingDomain.namespace,
            payload: .null,
            dryRun: true
        ),
        in: session
    )

    #expect(result.generation == DocumentGeneration(0))
    #expect(!result.didMutate)
    #expect(result.dryRun)
    #expect(result.automationResults.isEmpty)
    #expect(try stringValue(for: "outcome", in: result) == "failed")
    #expect(session.document.cadDocument.metadata.name == "Dry Printable")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityRejectsUnsupportedPayloadBeforeExecution() throws {
    let registry = try ManufacturingDomain.registry()
    let session = EditorSession(document: .empty(named: "Rejected"))
    var caught: EditorError?

    do {
        _ = try DomainCommandExecutor(registry: registry).execute(
            DomainCommandRequest(
                capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
                namespace: ManufacturingDomain.namespace,
                payload: .object([
                    "target": .string("body"),
                ])
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.document.cadDocument.metadata.name == "Rejected")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityRejectsInvalidBuildVolumeBeforeExecution() throws {
    let registry = try ManufacturingDomain.registry()
    let session = EditorSession(document: .empty(named: "Invalid Build Volume"))
    var caught: EditorError?

    do {
        _ = try DomainCommandExecutor(registry: registry).execute(
            DomainCommandRequest(
                capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
                namespace: ManufacturingDomain.namespace,
                payload: .object([
                    "buildVolume": .object([
                        "widthMeters": .number(0.1),
                        "depthMeters": .number(0.1),
                        "heightMeters": .number(0.0),
                    ]),
                ])
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.document.cadDocument.metadata.name == "Invalid Build Volume")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func manufacturingPrintabilityRejectsInvalidOverhangLimitBeforeExecution() throws {
    let registry = try ManufacturingDomain.registry()
    let session = EditorSession(document: .empty(named: "Invalid Overhang Limit"))
    var caught: EditorError?

    do {
        _ = try DomainCommandExecutor(registry: registry).execute(
            DomainCommandRequest(
                capabilityID: ManufacturingDomain.validatePrintabilityCapabilityID,
                namespace: ManufacturingDomain.namespace,
                payload: .object([
                    "overhangLimitDegrees": .number(120.0),
                ])
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.document.cadDocument.metadata.name == "Invalid Overhang Limit")
}

@MainActor
private func printableBoxSession(
    name: String,
    widthMeters: Double,
    heightMeters: Double,
    depthMeters: Double
) throws -> EditorSession {
    let session = EditorSession(document: .empty(named: name))
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Box",
            plane: .xy,
            width: .length(widthMeters, .meter),
            height: .length(heightMeters, .meter),
            depth: .length(depthMeters, .meter),
            direction: .normal
        )
    )
    return session
}

@MainActor
private func sheetSession(name: String) throws -> EditorSession {
    let session = EditorSession(document: .empty(named: name))
    _ = try session.execute(
        .createPolySplineSurface(
            name: "Sheet",
            sourceMesh: Mesh(
                positions: [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.02, y: 0.0, z: 0.0),
                    Point3D(x: 0.02, y: 0.0, z: 0.02),
                    Point3D(x: 0.0, y: 0.0, z: 0.02),
                ],
                indices: [
                    0, 1, 2,
                    0, 2, 3,
                ]
            ),
            options: PolySplineOptions(mergePatches: false)
        )
    )
    return session
}

@MainActor
private func closeBodiesSession(name: String) throws -> EditorSession {
    let session = EditorSession(document: .empty(named: name))
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "First Box",
            plane: .xy,
            firstCorner: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.01, .meter), y: .length(0.01, .meter)),
            depth: .length(0.01, .meter),
            direction: .normal
        )
    )
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Second Box",
            plane: .xy,
            firstCorner: SketchPoint(x: .length(0.0101, .meter), y: .length(0.0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.0201, .meter), y: .length(0.01, .meter)),
            depth: .length(0.01, .meter),
            direction: .normal
        )
    )
    return session
}

private func objectPayload(
    _ result: DomainExecutionResult
) throws -> [String: SemanticJSONValue] {
    guard case .object(let object) = try #require(result.payload) else {
        Issue.record("Expected domain execution payload to be an object.")
        return [:]
    }
    return object
}

private func stringValue(
    for key: String,
    in result: DomainExecutionResult
) throws -> String {
    let object = try objectPayload(result)
    return try stringValue(for: key, in: object)
}

private func stringValue(
    for key: String,
    in object: [String: SemanticJSONValue]
) throws -> String {
    guard case .string(let value) = try #require(object[key]) else {
        Issue.record("Expected \(key) to be a string.")
        return ""
    }
    return value
}

private func objectValue(
    for key: String,
    in result: DomainExecutionResult
) throws -> [String: SemanticJSONValue] {
    let object = try objectPayload(result)
    return try objectValue(for: key, in: object)
}

private func objectValue(
    for key: String,
    in object: [String: SemanticJSONValue]
) throws -> [String: SemanticJSONValue] {
    guard case .object(let value) = try #require(object[key]) else {
        Issue.record("Expected \(key) to be an object.")
        return [:]
    }
    return value
}

private func objectValue(
    _ value: SemanticJSONValue
) -> [String: SemanticJSONValue]? {
    guard case .object(let object) = value else {
        return nil
    }
    return object
}

private func arrayValue(
    for key: String,
    in result: DomainExecutionResult
) throws -> [SemanticJSONValue] {
    let object = try objectPayload(result)
    return try arrayValue(for: key, in: object)
}

private func arrayValue(
    for key: String,
    in object: [String: SemanticJSONValue]
) throws -> [SemanticJSONValue] {
    guard case .array(let value) = try #require(object[key]) else {
        Issue.record("Expected \(key) to be an array.")
        return []
    }
    return value
}

private func numberValue(
    for key: String,
    in result: DomainExecutionResult
) throws -> Double {
    let object = try objectPayload(result)
    return try numberValue(for: key, in: object)
}

private func numberValue(
    for key: String,
    in object: [String: SemanticJSONValue]
) throws -> Double {
    guard case .number(let value) = try #require(object[key]) else {
        Issue.record("Expected \(key) to be a number.")
        return .nan
    }
    return value
}

private func temporaryExportURL(pathExtension: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("rupa-manufacturing-\(UUID().uuidString)")
        .appendingPathExtension(pathExtension)
}

@MainActor
private func bodySceneNodeID(
    for featureID: FeatureID,
    in session: EditorSession
) throws -> SceneNodeID {
    guard let id = session.document.productMetadata.sceneNodes.first(
        where: { $0.value.reference == .body(featureID) }
    )?.key else {
        Issue.record("Expected a scene node for body feature \(featureID).")
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected a scene node for body feature \(featureID)."
        )
    }
    return id
}
