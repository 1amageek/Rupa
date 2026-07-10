import Foundation
import Testing
import RupaAutomation
import RupaCore
import RupaCoreTypes
@testable import RupaDomainFoundation

@Test(.timeLimit(.minutes(1)))
func domainRegistryRoutesDecoderValidatorAndLowering() throws {
    let namespace: SemanticNamespaceID = "architecture"
    let capabilityID: DomainCapabilityID = "architecture.createWall"
    let extensionID = SemanticExtensionID()
    let envelope = SemanticExtensionEnvelope(
        id: extensionID,
        namespace: namespace,
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object(["kind": .string("wall")]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: "wall-1",
                    ownership: .domainOwned,
                    sourcePaths: [.root]
                ),
            ]
        )
    )
    let registry = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: namespace,
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: capabilityID,
                namespace: namespace,
                name: "Create Wall",
                summary: "Create a semantic wall projection.",
                effect: .documentMutation,
                resultKind: .documentTransaction,
                supportsDryRun: true,
                targetKinds: ["site", "level"],
                failureMode: "Rejects invalid wall baselines before mutation."
            ),
        ],
        decoders: [CountingDecoder(namespace: namespace)],
        validators: [WarningValidator(namespace: namespace)],
        commandLowerings: [EmptyBatchLowering(capabilityID: capabilityID)]
    )

    let decoded = try registry.decode(envelope)
    #expect(decoded.extensionID == extensionID)
    #expect(decoded.semanticEntityCount == 1)

    let diagnostics = try registry.validate(
        envelope: envelope,
        in: DesignDocument.empty(named: "Domain")
    )
    #expect(diagnostics.map(\.message) == ["Domain validator reached architecture."])

    let request = DomainCommandRequest(
        capabilityID: capabilityID,
        namespace: namespace,
        payload: .object([:]),
        expectedGeneration: DocumentGeneration(7),
        dryRun: true
    )
    let plan = try registry.lower(request)
    guard case .automationBatch(let batch) = plan else {
        Issue.record("Expected automation batch plan.")
        return
    }
    #expect(batch.commands.isEmpty)
    #expect(batch.expectedGeneration == DocumentGeneration(7))

    #expect(registry.sortedCapabilityDescriptors().map(\.id) == [capabilityID])
}

@Test(.timeLimit(.minutes(1)))
func domainRegistryMergesIndependentRegistriesForCompositionRoots() throws {
    let manufacturing = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: "manufacturing",
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: "manufacturing.validatePrintability",
                namespace: "manufacturing",
                name: "Validate Printability",
                summary: "Validate printability.",
                effect: .query,
                resultKind: .semanticPayload,
                supportsDryRun: true,
                targetKinds: ["document"],
                failureMode: "Reports manufacturing diagnostics."
            ),
        ],
        commandLowerings: [
            EmptyBatchLowering(capabilityID: "manufacturing.validatePrintability"),
        ]
    )
    let architecture = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: "architecture",
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: "architecture.createWall",
                namespace: "architecture",
                name: "Create Wall",
                summary: "Create a wall.",
                effect: .documentMutation,
                resultKind: .documentTransaction,
                supportsDryRun: true,
                targetKinds: ["path", "level"],
                failureMode: "Rejects invalid wall inputs."
            ),
        ],
        commandLowerings: [
            EmptyBatchLowering(capabilityID: "architecture.createWall"),
        ]
    )

    let merged = try DomainRegistry.merged([manufacturing, architecture])

    #expect(merged.sortedCapabilityDescriptors().map(\.id.rawValue) == [
        "architecture.createWall",
        "manufacturing.validatePrintability",
    ])
    #expect(merged.namespaceRegistration(for: "manufacturing") != nil)
    #expect(merged.namespaceRegistration(for: "architecture") != nil)
}

@Test(.timeLimit(.minutes(1)))
func domainRegistryMergeRejectsDuplicateNamespaces() throws {
    let first = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: "manufacturing",
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ]
    )
    let second = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: "manufacturing",
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 2, patch: 0)]
            ),
        ]
    )
    var caught: DomainRegistryError?

    do {
        _ = try DomainRegistry.merged([first, second])
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .invalidRegistration)
    #expect(caught?.message == "Duplicate domain namespace manufacturing.")
}

@Test(.timeLimit(.minutes(1)))
func domainRegistryRoutesProjectionRepairAndSimulationAdapters() throws {
    let namespace: SemanticNamespaceID = "turbomachinery"
    let extensionID = SemanticExtensionID()
    let envelope = SemanticExtensionEnvelope(
        id: extensionID,
        namespace: namespace,
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object(["kind": .string("blade")]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: "blade-1",
                    ownership: .domainOwned,
                    sourcePaths: [.root]
                ),
            ]
        )
    )
    let registry = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: namespace,
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ],
        projectionRepairProviders: [EmptyRepairProvider(namespace: namespace)],
        simulationAdapters: [FixtureSimulationAdapter(namespace: namespace)]
    )

    let repairPlan = try registry.repairProjection(
        DomainProjectionRepairRequest(
            envelope: envelope,
            currentGeneration: DocumentGeneration(3),
            dryRun: true
        )
    )
    guard case .automationBatch(let repairBatch) = repairPlan else {
        Issue.record("Expected repair provider to return an automation batch.")
        return
    }
    #expect(repairBatch.expectedGeneration == DocumentGeneration(3))

    let simulationPlan = try registry.prepareSimulation(
        DomainSimulationRequest(
            namespace: namespace,
            semanticExtensionID: extensionID,
            payload: .object([:]),
            generation: DocumentGeneration(3)
        )
    )
    #expect(simulationPlan.namespace == namespace)
    #expect(simulationPlan.semanticExtensionID == extensionID)
    #expect(simulationPlan.artifactKind == "fixture-solver-input")
}

@Test(.timeLimit(.minutes(1)))
func domainCommandExecutorRunsAutomationBatchThroughCommandStack() throws {
    let namespace: SemanticNamespaceID = "architecture"
    let capabilityID: DomainCapabilityID = "architecture.rename"
    let registry = try executableRegistry(
        namespace: namespace,
        capabilityID: capabilityID,
        supportsDryRun: true,
        lowerings: [
            RenameBatchLowering(
                capabilityID: capabilityID,
                name: "Domain Renamed"
            ),
        ]
    )
    let session = EditorSession(document: .empty(named: "Before"))

    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:]),
            expectedGeneration: session.generation
        ),
        in: session
    )

    #expect(result.didMutate)
    #expect(result.wouldMutate)
    #expect(!result.dryRun)
    #expect(result.automationResults.count == 1)
    #expect(session.document.cadDocument.metadata.name == "Domain Renamed")
    #expect(session.commandStack.canUndo)
}

@Test(.timeLimit(.minutes(1)))
func domainCommandExecutorDryRunRestoresAutomationBatchMutation() throws {
    let namespace: SemanticNamespaceID = "architecture"
    let capabilityID: DomainCapabilityID = "architecture.rename"
    let registry = try executableRegistry(
        namespace: namespace,
        capabilityID: capabilityID,
        supportsDryRun: true,
        lowerings: [
            RenameBatchLowering(
                capabilityID: capabilityID,
                name: "Dry Run Name"
            ),
        ]
    )
    let session = EditorSession(document: .empty(named: "Before"))

    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:]),
            expectedGeneration: session.generation,
            dryRun: true
        ),
        in: session
    )

    #expect(!result.didMutate)
    #expect(result.wouldMutate)
    #expect(result.dryRun)
    #expect(result.baseGeneration == DocumentGeneration(0))
    #expect(result.generation == DocumentGeneration(0))
    #expect(result.proposedGeneration == DocumentGeneration(1))
    #expect(result.automationResults.count == 1)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(!session.commandStack.canUndo)
    #expect(session.generation == DocumentGeneration())
}

@Test(.timeLimit(.minutes(1)))
func domainCommandExecutorCommitsSemanticProjectionAsOneUndoEntry() throws {
    let namespace: SemanticNamespaceID = "manufacturing"
    let capabilityID: DomainCapabilityID = "manufacturing.rename"
    let extensionID = SemanticExtensionID()
    var document = DesignDocument.empty(named: "Before")
    let sourceFeatureID = try appendProjectionTestFeature(named: "Projection Source", to: &document)
    let registry = try executableRegistry(
        namespace: namespace,
        capabilityID: capabilityID,
        supportsDryRun: true,
        lowerings: [
            RenameSemanticTransactionLowering(
                capabilityID: capabilityID,
                name: "Editor Domain",
                extensionID: extensionID,
                sourceFeatureID: sourceFeatureID
            ),
        ]
    )
    let session = EditorSession(document: document)

    let result = try DomainCommandExecutor(registry: registry).execute(
        DomainCommandRequest(
            capabilityID: capabilityID,
            namespace: namespace,
            payload: .object([:]),
            expectedGeneration: session.generation
        ),
        in: session
    )

    #expect(result.didMutate)
    #expect(result.commandName == "manufacturing.renameTransaction")
    #expect(session.document.cadDocument.metadata.name == "Editor Domain")
    let committedEnvelope = try #require(
        session.document.productMetadata.semanticExtensions[extensionID]
    )
    let semanticEntity = try #require(
        committedEnvelope.projection.semanticEntities.first
    )
    let expectedDependencyIdentity = try ProjectionDependencyIdentityBuilder().identity(
        for: semanticEntity.id,
        in: committedEnvelope,
        document: session.document,
        generation: session.generation
    )
    #expect(semanticEntity.dependencyIdentity == expectedDependencyIdentity)
    #expect(session.commandStack.undoEntries.count == 1)

    _ = try session.undo()

    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.document.productMetadata.semanticExtensions[extensionID] == nil)
}

@Test(.timeLimit(.minutes(1)))
func domainCommandExecutorRollsBackUniversalMutationWhenSemanticBatchIsInvalid() throws {
    let namespace: SemanticNamespaceID = "architecture"
    let capabilityID: DomainCapabilityID = "architecture.invalidProjection"
    let registry = try executableRegistry(
        namespace: namespace,
        capabilityID: capabilityID,
        supportsDryRun: true,
        lowerings: [
            InvalidSemanticTransactionLowering(capabilityID: capabilityID),
        ]
    )
    let session = EditorSession(document: .empty(named: "Before"))

    #expect(throws: Error.self) {
        _ = try DomainCommandExecutor(registry: registry).execute(
            DomainCommandRequest(
                capabilityID: capabilityID,
                namespace: namespace,
                payload: .object([:]),
                expectedGeneration: session.generation
            ),
            in: session
        )
    }

    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.document.productMetadata.semanticExtensions.isEmpty)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.undoEntries.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func domainOwnershipResolverSupportsMixedOwnershipWithinOneEnvelope() throws {
    let envelope = SemanticExtensionEnvelope(
        namespace: "architecture",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object([:]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: "domain",
                    ownership: .domainOwned,
                    sourcePaths: [.root]
                ),
                ProjectionSemanticEntity(
                    id: "universal",
                    ownership: .universalOwned,
                    sourcePaths: [.root]
                ),
                ProjectionSemanticEntity(
                    id: "classified",
                    ownership: .classified,
                    sourcePaths: [.root]
                ),
            ]
        )
    )
    let resolver = DomainOwnershipResolver(
        registeredNamespaces: ["architecture"]
    )
    let document = DesignDocument.empty()

    let domain = try resolver.resolve(
        envelope: envelope,
        semanticEntityID: "domain",
        in: document,
        generation: DocumentGeneration()
    )
    let universal = try resolver.resolve(
        envelope: envelope,
        semanticEntityID: "universal",
        in: document,
        generation: DocumentGeneration()
    )
    let classified = try resolver.resolve(
        envelope: envelope,
        semanticEntityID: "classified",
        in: document,
        generation: DocumentGeneration()
    )

    #expect(domain.editRoute == .domainCapability)
    #expect(universal.editRoute == .universalCADCommand)
    #expect(classified.editRoute == .classificationUpdate)
    #expect([domain, universal, classified].allSatisfy { $0.freshness == .notApplicable })
}

@Test(.timeLimit(.minutes(1)))
func domainCommandExecutorRejectsUnsupportedDryRun() throws {
    let namespace: SemanticNamespaceID = "architecture"
    let capabilityID: DomainCapabilityID = "architecture.rename"
    let registry = try executableRegistry(
        namespace: namespace,
        capabilityID: capabilityID,
        supportsDryRun: false,
        lowerings: [
            RenameBatchLowering(
                capabilityID: capabilityID,
                name: "Rejected"
            ),
        ]
    )
    let session = EditorSession(document: .empty(named: "Before"))

    var caught: EditorError?
    do {
        _ = try DomainCommandExecutor(registry: registry).execute(
            DomainCommandRequest(
                capabilityID: capabilityID,
                namespace: namespace,
                payload: .object([:]),
                expectedGeneration: session.generation,
                dryRun: true
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.document.cadDocument.metadata.name == "Before")
}

@Test(.timeLimit(.minutes(1)))
func domainOwnershipResolverClassifiesRegisteredUnknownAndStaleProjections() throws {
    let registeredNamespace: SemanticNamespaceID = "architecture"
    let unknownNamespace: SemanticNamespaceID = "unknown.domain"
    let domainOwnedID = SemanticExtensionID()
    let universalOwnedID = SemanticExtensionID()
    let classifiedID = SemanticExtensionID()
    let unknownID = SemanticExtensionID()
    let currentGeneration = DocumentGeneration(4)
    let registry = try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: registeredNamespace,
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ]
    )
    var document = DesignDocument.empty()
    let domainFeatureID = try appendProjectionTestFeature(named: "Domain Source", to: &document)
    let universalFeatureID = try appendProjectionTestFeature(named: "Universal Source", to: &document)
    let classifiedFeatureID = try appendProjectionTestFeature(named: "Classified Source", to: &document)
    let unknownFeatureID = try appendProjectionTestFeature(named: "Unknown Source", to: &document)

    let domainEnvelope = try projectionTestEnvelope(
        id: domainOwnedID,
        namespace: registeredNamespace,
        semanticEntityID: "domain-owned",
        ownership: .domainOwned,
        featureID: domainFeatureID,
        document: document,
        generation: currentGeneration
    )
    let universalEnvelope = try projectionTestEnvelope(
        id: universalOwnedID,
        namespace: registeredNamespace,
        semanticEntityID: "universal-owned",
        ownership: .universalOwned,
        featureID: universalFeatureID,
        document: document,
        generation: DocumentGeneration(3)
    )
    let classifiedEnvelope = try projectionTestEnvelope(
        id: classifiedID,
        namespace: registeredNamespace,
        semanticEntityID: "classified",
        ownership: .classified,
        featureID: classifiedFeatureID,
        document: document,
        generation: DocumentGeneration(3)
    )
    let unknownEnvelope = try projectionTestEnvelope(
        id: unknownID,
        namespace: unknownNamespace,
        semanticEntityID: "unknown",
        ownership: .domainOwned,
        featureID: unknownFeatureID,
        document: document,
        generation: currentGeneration
    )

    document.cadDocument.designGraph.nodes[classifiedFeatureID]?.name = "Changed Classified Source"
    document.productMetadata.semanticExtensions = [
        domainOwnedID: domainEnvelope,
        universalOwnedID: universalEnvelope,
        classifiedID: classifiedEnvelope,
        unknownID: unknownEnvelope,
    ]

    let resolutions = Dictionary(
        uniqueKeysWithValues: try registry.ownershipResolver()
            .resolveAll(in: document, generation: currentGeneration)
            .map { ($0.extensionID, $0) }
    )

    #expect(resolutions[domainOwnedID]?.ownershipKind == .domainOwned)
    #expect(resolutions[domainOwnedID]?.editRoute == .domainCapability)
    #expect(resolutions[domainOwnedID]?.freshness == .current)

    #expect(resolutions[universalOwnedID]?.ownershipKind == .universalOwned)
    #expect(resolutions[universalOwnedID]?.editRoute == .universalCADCommand)
    #expect(resolutions[universalOwnedID]?.freshness == .current)

    #expect(resolutions[classifiedID]?.ownershipKind == .classified)
    #expect(resolutions[classifiedID]?.editRoute == .projectionRepair)
    #expect(resolutions[classifiedID]?.freshness == .stale)

    #expect(resolutions[unknownID]?.ownershipKind == .unknownNamespace)
    #expect(resolutions[unknownID]?.editRoute == .preserveOnly)
    #expect(resolutions[unknownID]?.isNamespaceRegistered == false)
}

private func projectionTestEnvelope(
    id: SemanticExtensionID,
    namespace: SemanticNamespaceID,
    semanticEntityID: SemanticEntityID,
    ownership: SemanticOwnershipPolicy,
    featureID: FeatureID,
    document: DesignDocument,
    generation: DocumentGeneration
) throws -> SemanticExtensionEnvelope {
    var envelope = SemanticExtensionEnvelope(
        id: id,
        namespace: namespace,
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object(["kind": .string(semanticEntityID.rawValue)]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: semanticEntityID,
                    ownership: ownership,
                    sourcePaths: [.root]
                ),
            ],
            sourceReferences: [
                ProjectionManifest.SourceReference(
                    semanticEntityID: semanticEntityID,
                    featureID: featureID,
                    ownership: ownership
                ),
            ]
        )
    )
    envelope.projection.semanticEntities[0].dependencyIdentity = try ProjectionDependencyIdentityBuilder().identity(
        for: semanticEntityID,
        in: envelope,
        document: document,
        generation: generation
    )
    return envelope
}

@discardableResult
private func appendProjectionTestFeature(
    named name: String,
    to document: inout DesignDocument
) throws -> FeatureID {
    try document.createExtrudedRectangle(
        name: name,
        plane: .xy,
        width: .length(10.0, .millimeter),
        height: .length(10.0, .millimeter),
        depth: .length(10.0, .millimeter),
        direction: .normal
    )
}

@Test(.timeLimit(.minutes(1)))
func domainRegistryRejectsDuplicateNamespaces() throws {
    let namespace: SemanticNamespaceID = "architecture"

    var caught: DomainRegistryError?
    do {
        _ = try DomainRegistry(
            namespaces: [
                DomainNamespaceRegistration(
                    namespace: namespace,
                    supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
                ),
                DomainNamespaceRegistration(
                    namespace: namespace,
                    supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
                ),
            ]
        )
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .duplicateNamespace)
}

@Test(.timeLimit(.minutes(1)))
func domainRegistryRejectsDuplicateProjectionRepairProviders() throws {
    let namespace: SemanticNamespaceID = "architecture"

    var caught: DomainRegistryError?
    do {
        _ = try DomainRegistry(
            namespaces: [
                DomainNamespaceRegistration(
                    namespace: namespace,
                    supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
                ),
            ],
            projectionRepairProviders: [
                EmptyRepairProvider(namespace: namespace),
                EmptyRepairProvider(namespace: namespace),
            ]
        )
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .duplicateProjectionRepairProvider)
}

@Test(.timeLimit(.minutes(1)))
func domainRegistryRejectsDuplicateSimulationAdapters() throws {
    let namespace: SemanticNamespaceID = "architecture"

    var caught: DomainRegistryError?
    do {
        _ = try DomainRegistry(
            namespaces: [
                DomainNamespaceRegistration(
                    namespace: namespace,
                    supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
                ),
            ],
            simulationAdapters: [
                FixtureSimulationAdapter(namespace: namespace),
                FixtureSimulationAdapter(namespace: namespace),
            ]
        )
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .duplicateSimulationAdapter)
}

@Test(.timeLimit(.minutes(1)))
func domainRegistryRejectsCapabilityForUnregisteredNamespace() throws {
    var caught: DomainRegistryError?
    do {
        _ = try DomainRegistry(
            capabilityDescriptors: [
                DomainCapabilityDescriptor(
                    id: "architecture.createWall",
                    namespace: "architecture",
                    name: "Create Wall",
                    summary: "Create a semantic wall projection.",
                    effect: .documentMutation,
                    resultKind: .documentTransaction,
                    supportsDryRun: true,
                    failureMode: "Rejects invalid wall baselines before mutation."
                ),
            ]
        )
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .missingNamespace)
}

@Test(.timeLimit(.minutes(1)))
func domainRegistryRejectsLoweringForUnregisteredCapability() throws {
    let namespace: SemanticNamespaceID = "architecture"

    var caught: DomainRegistryError?
    do {
        _ = try DomainRegistry(
            namespaces: [
                DomainNamespaceRegistration(
                    namespace: namespace,
                    supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
                ),
            ],
            commandLowerings: [EmptyBatchLowering(capabilityID: "architecture.createWall")]
        )
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .missingCapability)
}

@Test(.timeLimit(.minutes(1)))
func domainRegistryRejectsCapabilityWithoutLowering() throws {
    var caught: DomainRegistryError?

    do {
        _ = try DomainRegistry(
            namespaces: [
                DomainNamespaceRegistration(
                    namespace: "architecture",
                    supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
                ),
            ],
            capabilityDescriptors: [
                DomainCapabilityDescriptor(
                    id: "architecture.createWall",
                    namespace: "architecture",
                    name: "Create Wall",
                    summary: "Creates an architecture wall.",
                    effect: .documentMutation,
                    resultKind: .documentTransaction,
                    supportsDryRun: true,
                    failureMode: "Rejects invalid wall input."
                ),
            ]
        )
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .missingCommandLowering)
    #expect(caught?.message.contains("architecture.createWall") == true)
}

@Test(.timeLimit(.minutes(1)))
func domainRegistryRejectsCapabilityIDOutsideNamespace() throws {
    var caught: DomainRegistryError?

    do {
        _ = try DomainRegistry(
            namespaces: [
                DomainNamespaceRegistration(
                    namespace: "architecture",
                    supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
                ),
            ],
            capabilityDescriptors: [
                DomainCapabilityDescriptor(
                    id: "renameDocument",
                    namespace: "architecture",
                    name: "Rename",
                    summary: "Invalidly collides with a built-in capability name.",
                    effect: .documentMutation,
                    resultKind: .documentTransaction,
                    supportsDryRun: true,
                    failureMode: "Rejects invalid names."
                ),
            ],
            commandLowerings: [
                EmptyBatchLowering(capabilityID: "renameDocument"),
            ]
        )
    } catch let error as DomainRegistryError {
        caught = error
    }

    #expect(caught?.code == .invalidRegistration)
    #expect(caught?.message.contains("qualified by their namespace") == true)
}

private struct CountingDecoder: DomainPayloadDecoder {
    var namespace: SemanticNamespaceID

    func decode(_ envelope: SemanticExtensionEnvelope) throws -> DomainPayloadDecodingResult {
        DomainPayloadDecodingResult(
            extensionID: envelope.id,
            namespace: envelope.namespace,
            schemaVersion: envelope.schemaVersion,
            semanticEntityCount: envelope.projection.semanticEntities.count
        )
    }
}

private struct WarningValidator: DomainValidator {
    var namespace: SemanticNamespaceID

    func validate(
        envelope: SemanticExtensionEnvelope,
        in document: DesignDocument
    ) throws -> [EditorDiagnostic] {
        [
            EditorDiagnostic(
                severity: .warning,
                message: "Domain validator reached \(envelope.namespace.rawValue)."
            ),
        ]
    }
}

private struct EmptyBatchLowering: DomainCommandLowering {
    var capabilityID: DomainCapabilityID

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        .automationBatch(
            AutomationBatch(
                commands: [],
                expectedGeneration: request.expectedGeneration
            )
        )
    }
}

private struct RenameBatchLowering: DomainCommandLowering {
    var capabilityID: DomainCapabilityID
    var name: String

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        .automationBatch(
            AutomationBatch(
                commands: [.renameDocument(name: name)],
                expectedGeneration: request.expectedGeneration
            )
        )
    }
}

private struct RenameSemanticTransactionLowering: DomainCommandLowering {
    var capabilityID: DomainCapabilityID
    var name: String
    var extensionID: SemanticExtensionID
    var sourceFeatureID: FeatureID

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        .documentTransaction(
            DomainDocumentTransaction(
                name: "manufacturing.renameTransaction",
                sourceCommands: [.renameDocument(name: name)],
                semanticMutations: [
                    .upsert(
                        SemanticExtensionEnvelope(
                            id: extensionID,
                            namespace: "manufacturing",
                            schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
                            payload: .object(["name": .string(name)]),
                            projection: ProjectionManifest(
                                semanticEntities: [
                                    ProjectionSemanticEntity(
                                        id: "document-name",
                                        ownership: .classified,
                                        sourcePaths: [SemanticPayloadPath([.key("name")])]
                                    ),
                                ],
                                sourceReferences: [
                                    ProjectionManifest.SourceReference(
                                        semanticEntityID: "document-name",
                                        featureID: sourceFeatureID,
                                        ownership: .classified
                                    ),
                                ]
                            )
                        )
                    ),
                ],
                expectedGeneration: request.expectedGeneration
            )
        )
    }
}

private struct InvalidSemanticTransactionLowering: DomainCommandLowering {
    var capabilityID: DomainCapabilityID

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        let duplicateID: SemanticEntityID = "duplicate"
        return .documentTransaction(
            DomainDocumentTransaction(
                name: "architecture.invalidProjection",
                sourceCommands: [.renameDocument(name: "Must Roll Back")],
                semanticMutations: [
                    .upsert(
                        SemanticExtensionEnvelope(
                            namespace: request.namespace,
                            schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
                            payload: .object([:]),
                            projection: ProjectionManifest(
                                semanticEntities: [
                                    ProjectionSemanticEntity(
                                        id: duplicateID,
                                        ownership: .domainOwned,
                                        sourcePaths: [.root]
                                    ),
                                    ProjectionSemanticEntity(
                                        id: duplicateID,
                                        ownership: .classified,
                                        sourcePaths: [.root]
                                    ),
                                ]
                            )
                        )
                    ),
                ],
                expectedGeneration: request.expectedGeneration
            )
        )
    }
}

private func executableRegistry(
    namespace: SemanticNamespaceID,
    capabilityID: DomainCapabilityID,
    supportsDryRun: Bool,
    lowerings: [any DomainCommandLowering]
) throws -> DomainRegistry {
    try DomainRegistry(
        namespaces: [
            DomainNamespaceRegistration(
                namespace: namespace,
                supportedSchemaVersions: [SemanticSchemaVersion(major: 0, minor: 1, patch: 0)]
            ),
        ],
        capabilityDescriptors: [
            DomainCapabilityDescriptor(
                id: capabilityID,
                namespace: namespace,
                name: capabilityID.rawValue,
                summary: "Execute a fixture domain capability.",
                effect: .documentMutation,
                resultKind: .documentTransaction,
                supportsDryRun: supportsDryRun,
                targetKinds: ["document"],
                failureMode: "Rejects invalid fixture requests."
            ),
        ],
        commandLowerings: lowerings
    )
}

private struct EmptyRepairProvider: DomainProjectionRepairProvider {
    var namespace: SemanticNamespaceID

    func repairProjection(_ request: DomainProjectionRepairRequest) throws -> DomainCommandPlan {
        .automationBatch(
            AutomationBatch(
                commands: [],
                expectedGeneration: request.currentGeneration
            )
        )
    }
}

private struct FixtureSimulationAdapter: DomainSimulationAdapter {
    var namespace: SemanticNamespaceID

    func prepareSimulation(_ request: DomainSimulationRequest) throws -> DomainSimulationPlan {
        DomainSimulationPlan(
            namespace: namespace,
            semanticExtensionID: request.semanticExtensionID,
            generation: request.generation,
            artifactKind: "fixture-solver-input",
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: "Simulation adapter prepared \(namespace.rawValue)."
                ),
            ]
        )
    }
}
