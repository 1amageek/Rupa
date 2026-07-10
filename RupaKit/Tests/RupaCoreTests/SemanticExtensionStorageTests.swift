import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func semanticExtensionsRoundTripThroughProductPackage() throws {
    let temporaryDirectory = try semanticExtensionTemporaryDirectory()
    defer {
        removeSemanticExtensionTemporaryDirectory(temporaryDirectory)
    }

    let extensionID = SemanticExtensionID()
    let envelope = SemanticExtensionEnvelope(
        id: extensionID,
        namespace: "architecture",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object([
            "kind": .string("wall"),
            "height": .number(3.2),
            "layers": .array([
                .object(["material": .string("gypsum")]),
                .object(["material": .string("stud")]),
            ]),
        ]),
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

    var document = DesignDocument.empty(named: "Semantic House")
    document.productMetadata.semanticExtensions = [extensionID: envelope]

    let url = temporaryDirectory.appendingPathComponent("semantic-house.swcad")
    let service = DocumentFileService()
    try service.save(document, to: url)
    let loaded = try service.load(from: url)

    #expect(loaded.productMetadata.semanticExtensions == [extensionID: envelope])
}

@Test(.timeLimit(.minutes(1)))
func semanticExtensionsDecodeLegacyMetadataWithoutField() throws {
    let metadata = ProductMetadata.empty()
    let encoded = try JSONEncoder().encode(metadata)
    let object = try JSONSerialization.jsonObject(with: encoded)
    guard var dictionary = object as? [String: Any] else {
        Issue.record("Encoded ProductMetadata must be a dictionary.")
        return
    }
    dictionary.removeValue(forKey: "semanticExtensions")

    let legacyData = try JSONSerialization.data(withJSONObject: dictionary)
    let decoded = try JSONDecoder().decode(ProductMetadata.self, from: legacyData)

    #expect(decoded.semanticExtensions.isEmpty)
    try decoded.validate(
        against: CADDocument(units: .meters, metadata: DocumentMetadata(name: "Legacy")),
        objectRegistry: .builtIn
    )
}

@Test(.timeLimit(.minutes(1)))
func semanticExtensionsEncodeAsUUIDKeyedObject() throws {
    let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
    let extensionID = SemanticExtensionID(uuid)
    var metadata = ProductMetadata.empty()
    metadata.semanticExtensions = [
        extensionID: SemanticExtensionEnvelope(
            id: extensionID,
            namespace: "architecture",
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
        ),
    ]

    let encoded = try JSONEncoder().encode(metadata)
    let object = try JSONSerialization.jsonObject(with: encoded)
    let dictionary = try #require(object as? [String: Any])
    let semanticExtensions = try #require(dictionary["semanticExtensions"] as? [String: Any])
    let envelope = try #require(semanticExtensions[uuid.uuidString] as? [String: Any])

    #expect(envelope["id"] as? String == uuid.uuidString)
    #expect(envelope["namespace"] as? String == "architecture")
    let projection = try #require(envelope["projection"] as? [String: Any])
    let semanticEntities = try #require(projection["semanticEntities"] as? [[String: Any]])
    #expect(semanticEntities.first?["ownership"] as? String == "domainOwned")
}

@Test(.timeLimit(.minutes(1)))
func semanticExtensionsRejectInvalidUUIDDictionaryKeys() throws {
    let metadata = ProductMetadata.empty()
    let encoded = try JSONEncoder().encode(metadata)
    let object = try JSONSerialization.jsonObject(with: encoded)
    guard var dictionary = object as? [String: Any] else {
        Issue.record("Encoded ProductMetadata must be a dictionary.")
        return
    }
    dictionary["semanticExtensions"] = [
        "not-a-uuid": [
            "id": UUID().uuidString,
            "namespace": "architecture",
            "schemaVersion": ["major": 0, "minor": 1, "patch": 0],
            "payload": [:],
            "projection": [
                "semanticEntities": [],
                "sourceReferences": [],
                "sceneReferences": [],
                "topologyReferences": [],
                "boundaryTags": [],
            ],
        ],
    ]
    let invalidData = try JSONSerialization.data(withJSONObject: dictionary)

    do {
        _ = try JSONDecoder().decode(ProductMetadata.self, from: invalidData)
        Issue.record("Invalid semantic extension dictionary key should fail decoding.")
    } catch DecodingError.dataCorrupted {
    } catch {
        Issue.record("Expected data corrupted error, got \(error).")
    }
}

@Test(.timeLimit(.minutes(1)))
func topologyMaterialBindingsDecodeLegacyMetadataWithoutField() throws {
    let metadata = ProductMetadata.empty()
    let encoded = try JSONEncoder().encode(metadata)
    let object = try JSONSerialization.jsonObject(with: encoded)
    guard var dictionary = object as? [String: Any] else {
        Issue.record("Encoded ProductMetadata must be a dictionary.")
        return
    }
    dictionary.removeValue(forKey: "topologyMaterialBindings")

    let legacyData = try JSONSerialization.data(withJSONObject: dictionary)
    let decoded = try JSONDecoder().decode(ProductMetadata.self, from: legacyData)

    #expect(decoded.topologyMaterialBindings.isEmpty)
    try decoded.validate(
        against: CADDocument(units: .meters, metadata: DocumentMetadata(name: "Legacy")),
        objectRegistry: .builtIn
    )
}

@Test(.timeLimit(.minutes(1)))
func topologyMaterialBindingsEncodeAsUUIDKeyedObject() throws {
    let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000321"))
    let bindingID = TopologyMaterialBinding.ID(uuid)
    let (metadata, binding) = try topologyMaterialBindingFixture(bindingID: bindingID)

    let encoded = try JSONEncoder().encode(metadata)
    let object = try JSONSerialization.jsonObject(with: encoded)
    let dictionary = try #require(object as? [String: Any])
    let topologyMaterialBindings = try #require(dictionary["topologyMaterialBindings"] as? [String: Any])
    let encodedBinding = try #require(topologyMaterialBindings[uuid.uuidString] as? [String: Any])
    let decoded = try JSONDecoder().decode(ProductMetadata.self, from: encoded)

    #expect(encodedBinding["id"] as? String == uuid.uuidString)
    #expect(decoded.topologyMaterialBindings == [bindingID: binding])
}

@Test(.timeLimit(.minutes(1)))
func topologyMaterialBindingsRejectInvalidUUIDDictionaryKeys() throws {
    let bindingID = TopologyMaterialBinding.ID()
    let (metadata, _) = try topologyMaterialBindingFixture(bindingID: bindingID)
    let encoded = try JSONEncoder().encode(metadata)
    let object = try JSONSerialization.jsonObject(with: encoded)
    guard var dictionary = object as? [String: Any],
          let topologyMaterialBindings = dictionary["topologyMaterialBindings"] as? [String: Any],
          let bindingObject = topologyMaterialBindings[bindingID.rawValue.uuidString] else {
        Issue.record("Encoded ProductMetadata must contain one topology material binding.")
        return
    }
    dictionary["topologyMaterialBindings"] = [
        "not-a-uuid": bindingObject,
    ]
    let invalidData = try JSONSerialization.data(withJSONObject: dictionary)

    do {
        _ = try JSONDecoder().decode(ProductMetadata.self, from: invalidData)
        Issue.record("Invalid topology material binding dictionary key should fail decoding.")
    } catch DecodingError.dataCorrupted {
    } catch {
        Issue.record("Expected data corrupted error, got \(error).")
    }
}

@Test(.timeLimit(.minutes(1)))
func semanticExtensionValidationRejectsKeyMismatch() throws {
    let keyID = SemanticExtensionID()
    let envelope = SemanticExtensionEnvelope(
        id: SemanticExtensionID(),
        namespace: "architecture",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object([:])
    )
    var document = DesignDocument.empty(named: "Invalid Semantic")
    document.productMetadata.semanticExtensions = [keyID: envelope]

    var caught: DocumentValidationError?
    do {
        try document.validate()
    } catch let error as DocumentValidationError {
        caught = error
    }

    guard case .invalidProductMetadata(let message) = caught else {
        Issue.record("Expected invalid product metadata.")
        return
    }
    #expect(message.contains("Semantic extension keys"))
}

@Test(.timeLimit(.minutes(1)))
func semanticProjectionValidationRejectsMissingSourceFeature() throws {
    let extensionID = SemanticExtensionID()
    var document = DesignDocument.empty(named: "Invalid Projection")
    let envelope = SemanticExtensionEnvelope(
        id: extensionID,
        namespace: "architecture",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object([:]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: "wall-1",
                    ownership: .domainOwned,
                    sourcePaths: [.root],
                    dependencyIdentity: ProjectionDependencyIdentity(
                        documentID: document.id,
                        generation: DocumentGeneration(),
                        fingerprint: try .init(
                            algorithm: "fixture-dependencies-v1",
                            value: "missing-source"
                        )
                    )
                ),
            ],
            sourceReferences: [
                ProjectionManifest.SourceReference(
                    semanticEntityID: "wall-1",
                    featureID: FeatureID(),
                    ownership: .domainOwned
                ),
            ]
        )
    )
    document.productMetadata.semanticExtensions = [extensionID: envelope]

    var caught: DocumentValidationError?
    do {
        try document.validate()
    } catch let error as DocumentValidationError {
        caught = error
    }

    guard case .invalidProductMetadata(let message) = caught else {
        Issue.record("Expected invalid product metadata.")
        return
    }
    #expect(message.contains("existing CAD features"))
}

@Test(.timeLimit(.minutes(1)))
func semanticProjectionValidationRejectsSourceMappingWithoutDependencyIdentity() throws {
    var document = DesignDocument.empty(named: "Missing Projection Identity")
    let featureID = try semanticProjectionBox(named: "Source", in: &document)
    let extensionID = SemanticExtensionID()
    document.productMetadata.semanticExtensions[extensionID] = SemanticExtensionEnvelope(
        id: extensionID,
        namespace: "architecture",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object(["wall": .bool(true)]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: "wall",
                    ownership: .domainOwned,
                    sourcePaths: [SemanticPayloadPath([.key("wall")])]
                ),
            ],
            sourceReferences: [
                ProjectionManifest.SourceReference(
                    semanticEntityID: "wall",
                    featureID: featureID,
                    ownership: .domainOwned
                ),
            ]
        )
    )

    var caught: DocumentValidationError?
    do {
        try document.validate()
    } catch let error as DocumentValidationError {
        caught = error
    }

    guard case .invalidProductMetadata(let message) = caught else {
        Issue.record("Expected invalid product metadata.")
        return
    }
    #expect(message.contains("dependency identities"))
}

@Test(.timeLimit(.minutes(1)))
func semanticProjectionValidationRejectsConflictingSourceMappingOwnership() throws {
    var document = DesignDocument.empty(named: "Conflicting Projection Mapping")
    let featureID = try semanticProjectionBox(named: "Source", in: &document)
    let extensionID = SemanticExtensionID()
    let dependencyIdentity = ProjectionDependencyIdentity(
        documentID: document.id,
        generation: DocumentGeneration(),
        fingerprint: try .init(
            algorithm: "fixture-dependencies-v1",
            value: "conflicting-source-mapping"
        )
    )
    document.productMetadata.semanticExtensions[extensionID] = SemanticExtensionEnvelope(
        id: extensionID,
        namespace: "architecture",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object(["wall": .bool(true)]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: "wall",
                    ownership: .domainOwned,
                    sourcePaths: [SemanticPayloadPath([.key("wall")])],
                    dependencyIdentity: dependencyIdentity
                ),
            ],
            sourceReferences: [
                ProjectionManifest.SourceReference(
                    semanticEntityID: "wall",
                    featureID: featureID,
                    ownership: .domainOwned
                ),
                ProjectionManifest.SourceReference(
                    semanticEntityID: "wall",
                    featureID: featureID,
                    ownership: .universalOwned
                ),
            ]
        )
    )

    var caught: DocumentValidationError?
    do {
        try document.validate()
    } catch let error as DocumentValidationError {
        caught = error
    }

    guard case .invalidProductMetadata(let message) = caught else {
        Issue.record("Expected invalid product metadata.")
        return
    }
    #expect(message.contains("mapping targets must be unique"))
}

@Test(.timeLimit(.minutes(1)))
func semanticProjectionValidationRejectsTopologyNameWithDifferentOwner() throws {
    var document = DesignDocument.empty(named: "Invalid Projection Topology")
    let namedFeatureID = try semanticProjectionBox(named: "Named Source", in: &document)
    let declaredOwnerID = try semanticProjectionBox(named: "Declared Owner", in: &document)
    let extensionID = SemanticExtensionID()
    document.productMetadata.semanticExtensions[extensionID] = SemanticExtensionEnvelope(
        id: extensionID,
        namespace: "architecture",
        schemaVersion: SemanticSchemaVersion(major: 0, minor: 1, patch: 0),
        payload: .object(["wall": .bool(true)]),
        projection: ProjectionManifest(
            semanticEntities: [
                ProjectionSemanticEntity(
                    id: "wall",
                    ownership: .classified,
                    sourcePaths: [SemanticPayloadPath([.key("wall")])],
                    dependencyIdentity: ProjectionDependencyIdentity(
                        documentID: document.id,
                        generation: DocumentGeneration(),
                        fingerprint: try .init(
                            algorithm: "fixture-dependencies-v1",
                            value: "mismatched-topology-owner"
                        )
                    )
                ),
            ],
            topologyReferences: [
                ProjectionManifest.TopologyReference(
                    semanticEntityID: "wall",
                    persistentName: "feature:\(namedFeatureID.description)/generated:front",
                    role: .face,
                    owningFeatureID: declaredOwnerID
                ),
            ]
        )
    )

    var caught: DocumentValidationError?
    do {
        try document.validate()
    } catch let error as DocumentValidationError {
        caught = error
    }

    guard case .invalidProductMetadata(let message) = caught else {
        Issue.record("Expected invalid product metadata.")
        return
    }
    #expect(message.contains("must contain their owning CAD feature"))
}

@Test(.timeLimit(.minutes(1)))
func semanticJSONRejectsNonFiniteNumbers() throws {
    let value = SemanticJSONValue.number(.infinity)

    var caught: DocumentValidationError?
    do {
        try value.validate()
    } catch let error as DocumentValidationError {
        caught = error
    }

    guard case .invalidProductMetadata(let message) = caught else {
        Issue.record("Expected invalid product metadata.")
        return
    }
    #expect(message.contains("finite"))
}

private func topologyMaterialBindingFixture(
    bindingID: TopologyMaterialBinding.ID
) throws -> (ProductMetadata, TopologyMaterialBinding) {
    var metadata = ProductMetadata.empty()
    let sceneNodeID = try #require(metadata.rootSceneNodeIDs.first)
    let material = Material(
        name: "PETG",
        baseColor: ColorRGBA(r: 0.1, g: 0.5, b: 0.8, a: 1.0),
        metallic: 0.0,
        roughness: 0.45,
        opacity: 1.0
    )
    metadata.materialLibrary = MaterialLibrary(
        materials: [material.id: material],
        defaultMaterialID: material.id
    )
    let binding = TopologyMaterialBinding(
        id: bindingID,
        target: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .face(.generatedTopology("feature:box/generated:front"))
        ),
        materialID: material.id,
        process: TopologyMaterialBinding.Process(
            namespace: "manufacturing",
            processID: "fff"
        )
    )
    metadata.topologyMaterialBindings = [bindingID: binding]
    return (metadata, binding)
}

private func semanticExtensionTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}

private func removeSemanticExtensionTemporaryDirectory(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}

private func semanticProjectionBox(
    named name: String,
    in document: inout DesignDocument
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
