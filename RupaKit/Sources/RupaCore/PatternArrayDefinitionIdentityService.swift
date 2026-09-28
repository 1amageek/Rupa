import Foundation
import SwiftCAD
import RupaCoreTypes
import RupaProjectModel

public struct PatternArrayDefinitionIdentityService: Sendable {
    private static let algorithm = "sha256-pattern-definition-identity-v2"

    public init() {}

    /// The definition's identity: its scene structure, its CAD feature closure and the content of
    /// the authored meshes it presents, so a change to any of them is seen as a new definition.
    public func identity(
        for definition: ComponentDefinition,
        metadata: ProductMetadata,
        cadDocument: CADDocument,
        authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset] = [:]
    ) throws -> PatternArrayDefinitionIdentity {
        try identity(for: definition, metadata: metadata, cadDocument: cadDocument,
            authoredMeshAssets: authoredMeshAssets, ancestors: [])
    }

    private func identity(
        for definition: ComponentDefinition, metadata: ProductMetadata, cadDocument: CADDocument,
        authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset], ancestors: Set<ComponentDefinitionID>
    ) throws -> PatternArrayDefinitionIdentity {
        guard !ancestors.contains(definition.id) else {
            throw EditorError(code: .commandInvalid, message: "Pattern definitions cannot contain recursive instances.")
        }
        let ancestors = ancestors.union([definition.id])
        let sourceFeatureIDs = try featureClosure(
            for: definition,
            metadata: metadata,
            cadDocument: cadDocument
        )
        var meshIDs: Set<GeometrySourceID> = []
        var instanceIDs: Set<ComponentInstanceID> = []
        var pending = definition.rootSceneNodeIDs
        while let id = pending.popLast() {
            guard let node = metadata.sceneNodes[id] else { continue }
            meshIDs.formUnion(PatternArrayIndependentCopyBuilder.authoredMeshIDs(of: node))
            if let id = node.reference?.componentInstanceID { instanceIDs.insert(id) }
            pending.append(contentsOf: node.childIDs)
        }
        let meshEncoder = JSONEncoder()
        meshEncoder.outputFormatting = [.sortedKeys]
        let meshDigests = try meshIDs.sorted { $0.description < $1.description }.map { id -> String in
            guard let asset = authoredMeshAssets[id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Pattern array definition identity requires the meshes the definition presents."
                )
            }
            return PatternArrayStableDigest.hexDigest(for: try meshEncoder.encode(asset.source))
        }
        let instanceDigests = try instanceIDs.sorted { $0.description < $1.description }.map { id -> String in
            guard let instance = metadata.componentInstances[id],
                  let nested = metadata.componentDefinitions[instance.definitionID] else {
                throw EditorError(code: .referenceUnresolved, message: "A pattern instance has no definition.")
            }
            let nestedIdentity = try identity(for: nested, metadata: metadata, cadDocument: cadDocument,
                authoredMeshAssets: authoredMeshAssets, ancestors: ancestors)
            let instanceDigest = PatternArrayStableDigest.hexDigest(for: try meshEncoder.encode(instance))
            return instanceDigest + nestedIdentity.value
        }
        guard !sourceFeatureIDs.isEmpty || !meshDigests.isEmpty || !instanceDigests.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array definition identity requires cloneable CAD feature scene nodes."
            )
        }
        let featureTokenByID = featureTokenMap(for: sourceFeatureIDs)
        let featureIDTokenByID = try PatternArrayFeatureIDTokenMapService().tokenMap(for: sourceFeatureIDs)
        var payload = try PatternArrayDefinitionIdentityPayload(
            definition: definition,
            metadata: metadata,
            cadDocument: cadDocument,
            orderedFeatureIDs: sourceFeatureIDs,
            featureTokenByID: featureTokenByID,
            featureIDTokenByID: featureIDTokenByID
        )
        // Absent for a CAD-only definition, so its identity is unchanged from before meshes counted.
        payload.meshes = meshDigests.isEmpty ? nil : meshDigests
        payload.instances = instanceDigests.isEmpty ? nil : instanceDigests
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return PatternArrayDefinitionIdentity(
            algorithm: Self.algorithm,
            value: PatternArrayStableDigest.hexDigest(for: data)
        )
    }

    func featureClosure(
        for definition: ComponentDefinition,
        metadata: ProductMetadata,
        cadDocument: CADDocument
    ) throws -> [FeatureID] {
        var referencedFeatureIDs: Set<FeatureID> = []
        for rootSceneNodeID in definition.rootSceneNodeIDs {
            try collectReferencedFeatureIDs(
                rootSceneNodeID,
                metadata: metadata,
                featureIDs: &referencedFeatureIDs
            )
        }
        guard !referencedFeatureIDs.isEmpty else {
            return []
        }

        var closureFeatureIDs = referencedFeatureIDs
        var pendingFeatureIDs = Array(referencedFeatureIDs)
        while let featureID = pendingFeatureIDs.popLast() {
            guard let feature = cadDocument.designGraph.nodes[featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Pattern array definition identity requires existing CAD features."
                )
            }
            for input in feature.inputs where closureFeatureIDs.insert(input.featureID).inserted {
                pendingFeatureIDs.append(input.featureID)
            }
        }

        let orderedFeatureIDs = cadDocument.designGraph.order.filter {
            closureFeatureIDs.contains($0)
        }
        guard orderedFeatureIDs.count == closureFeatureIDs.count else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array definition identity requires a fully ordered CAD feature closure."
            )
        }
        return orderedFeatureIDs
    }

    private func collectReferencedFeatureIDs(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        featureIDs: inout Set<FeatureID>
    ) throws {
        guard let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array definition identity requires existing scene nodes."
            )
        }
        if let featureID = sceneNode.reference?.featureID {
            featureIDs.insert(featureID)
        }
        if let featureID = sceneNode.object?.sourceFeatureID {
            featureIDs.insert(featureID)
        }
        if let featureID = sceneNode.object?.sourceSection?.featureID {
            featureIDs.insert(featureID)
        }
        for childID in sceneNode.childIDs {
            try collectReferencedFeatureIDs(
                childID,
                metadata: metadata,
                featureIDs: &featureIDs
            )
        }
    }

    private func featureTokenMap(for featureIDs: [FeatureID]) -> [FeatureID: String] {
        Dictionary(
            uniqueKeysWithValues: featureIDs.enumerated().map { index, featureID in
                (featureID, "feature-\(index)")
            }
        )
    }
}

private struct PatternArrayDefinitionIdentityPayload: Encodable {
    var rootSceneNodes: [PatternArrayDefinitionSceneNodeIdentity]
    var features: [PatternArrayDefinitionFeatureIdentity]
    var meshes: [String]? = nil
    var instances: [String]? = nil

    init(
        definition: ComponentDefinition,
        metadata: ProductMetadata,
        cadDocument: CADDocument,
        orderedFeatureIDs: [FeatureID],
        featureTokenByID: [FeatureID: String],
        featureIDTokenByID: [FeatureID: FeatureID]
    ) throws {
        rootSceneNodes = try definition.rootSceneNodeIDs.map { rootSceneNodeID in
            try PatternArrayDefinitionSceneNodeIdentity(
                sceneNodeID: rootSceneNodeID,
                metadata: metadata,
                featureTokenByID: featureTokenByID
            )
        }
        features = try orderedFeatureIDs.map { featureID in
            guard let feature = cadDocument.designGraph.nodes[featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Pattern array definition identity requires existing CAD features."
                )
            }
            return try PatternArrayDefinitionFeatureIdentity(
                feature: feature,
                featureToken: try Self.featureToken(for: featureID, featureTokenByID: featureTokenByID),
                featureIDTokenByID: featureIDTokenByID
            )
        }
    }

    private static func featureToken(
        for featureID: FeatureID,
        featureTokenByID: [FeatureID: String]
    ) throws -> String {
        guard let token = featureTokenByID[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array definition identity found an ordered feature outside the clone closure."
            )
        }
        return token
    }
}

private struct PatternArrayDefinitionSceneNodeIdentity: Encodable {
    var reference: PatternArrayDefinitionSceneReferenceIdentity?
    var object: PatternArrayDefinitionObjectIdentity?
    var isVisible: Bool
    var isLocked: Bool
    var localTransform: [Double]
    var materialID: String?
    var children: [PatternArrayDefinitionSceneNodeIdentity]

    init(
        sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        featureTokenByID: [FeatureID: String]
    ) throws {
        guard let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array definition identity requires existing scene nodes."
            )
        }
        reference = try sceneNode.reference.map {
            try PatternArrayDefinitionSceneReferenceIdentity(
                reference: $0,
                featureTokenByID: featureTokenByID
            )
        }
        object = try sceneNode.object.map {
            try PatternArrayDefinitionObjectIdentity(
                object: $0,
                featureTokenByID: featureTokenByID
            )
        }
        isVisible = sceneNode.isVisible
        isLocked = sceneNode.isLocked
        localTransform = sceneNode.localTransform.matrix.values
        materialID = sceneNode.materialID?.description
        children = try sceneNode.childIDs.map { childID in
            try PatternArrayDefinitionSceneNodeIdentity(
                sceneNodeID: childID,
                metadata: metadata,
                featureTokenByID: featureTokenByID
            )
        }
    }
}

private struct PatternArrayDefinitionSceneReferenceIdentity: Encodable {
    var kind: SceneNodeReference.Kind
    var featureToken: String?
    var constructionPlaneID: String?
    var componentInstanceID: String?

    init(
        reference: SceneNodeReference,
        featureTokenByID: [FeatureID: String]
    ) throws {
        kind = reference.kind
        featureToken = try reference.featureID.map {
            try Self.featureToken(for: $0, featureTokenByID: featureTokenByID)
        }
        constructionPlaneID = reference.constructionPlaneID?.description
        componentInstanceID = reference.componentInstanceID?.description
    }

    private static func featureToken(
        for featureID: FeatureID,
        featureTokenByID: [FeatureID: String]
    ) throws -> String {
        guard let token = featureTokenByID[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array definition identity found a scene feature outside the clone closure."
            )
        }
        return token
    }
}

private struct PatternArrayDefinitionObjectIdentity: Encodable {
    var category: ObjectDescriptor.Category
    var geometryRole: ObjectDescriptor.GeometryRole?
    var typeID: String?
    var properties: [PatternArrayDefinitionObjectPropertyIdentity]
    var sourceFeatureToken: String?
    var sourceSection: PatternArrayDefinitionObjectSourceSectionIdentity?

    init(
        object: ObjectDescriptor,
        featureTokenByID: [FeatureID: String]
    ) throws {
        category = object.category
        geometryRole = object.geometryRole
        typeID = object.typeID?.rawValue
        properties = object.properties.values
            .sorted { lhs, rhs in lhs.key.rawValue < rhs.key.rawValue }
            .map {
                PatternArrayDefinitionObjectPropertyIdentity(
                    id: $0.key.rawValue,
                    value: $0.value
                )
            }
        sourceFeatureToken = try object.sourceFeatureID.map {
            try Self.featureToken(for: $0, featureTokenByID: featureTokenByID)
        }
        sourceSection = try object.sourceSection.map {
            try PatternArrayDefinitionObjectSourceSectionIdentity(
                sourceSection: $0,
                featureTokenByID: featureTokenByID
            )
        }
    }

    private static func featureToken(
        for featureID: FeatureID,
        featureTokenByID: [FeatureID: String]
    ) throws -> String {
        guard let token = featureTokenByID[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array definition identity found an object feature outside the clone closure."
            )
        }
        return token
    }
}

private struct PatternArrayDefinitionObjectSourceSectionIdentity: Encodable {
    var role: FeaturePort
    var featureToken: String
    var profileIndex: Int?

    init(
        sourceSection: BodySourceSectionReference,
        featureTokenByID: [FeatureID: String]
    ) throws {
        role = sourceSection.requiredOutputRole
        featureToken = try Self.featureToken(
            for: sourceSection.featureID,
            featureTokenByID: featureTokenByID
        )
        profileIndex = sourceSection.profileReference?.profileIndex
    }

    private static func featureToken(
        for featureID: FeatureID,
        featureTokenByID: [FeatureID: String]
    ) throws -> String {
        guard let token = featureTokenByID[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array definition identity found an object source section outside the clone closure."
            )
        }
        return token
    }
}

private struct PatternArrayDefinitionObjectPropertyIdentity: Encodable {
    var id: String
    var value: ObjectPropertyValue
}

private struct PatternArrayDefinitionFeatureIdentity: Encodable {
    var featureToken: String
    var name: String?
    var operation: FeatureOperation
    var inputs: [PatternArrayDefinitionFeatureInputIdentity]
    var outputs: [PatternArrayDefinitionFeatureOutputIdentity]
    var isSuppressed: Bool

    init(
        feature: FeatureNode,
        featureToken: String,
        featureIDTokenByID: [FeatureID: FeatureID]
    ) throws {
        let tokenized = try feature.remappingFeatureReferences(featureIDTokenByID)
        self.featureToken = featureToken
        name = feature.name
        operation = tokenized.operation
        inputs = tokenized.inputs.map(PatternArrayDefinitionFeatureInputIdentity.init)
        outputs = tokenized.outputs.map(PatternArrayDefinitionFeatureOutputIdentity.init)
        isSuppressed = feature.isSuppressed
    }
}

private struct PatternArrayDefinitionFeatureInputIdentity: Encodable {
    var featureID: FeatureID
    var role: FeaturePort

    init(input: FeatureInput) {
        featureID = input.featureID
        role = input.role
    }
}

private struct PatternArrayDefinitionFeatureOutputIdentity: Encodable {
    var role: FeaturePort

    init(output: FeatureOutput) {
        role = output.role
    }
}
