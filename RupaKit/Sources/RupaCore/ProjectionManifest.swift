import Foundation
import SwiftCAD
import RupaCoreTypes

public struct ProjectionManifest: Codable, Hashable, Sendable {
    public enum TopologyRole: String, Codable, Hashable, Sendable {
        case body
        case face
        case edge
        case vertex
        case profile
        case boundary
        case other
    }

    public enum BoundaryTarget: Codable, Hashable, Sendable {
        case semanticEntity(SemanticEntityID)
        case sourceFeature(FeatureID)
        case sceneNode(SceneNodeID)
        case topology(persistentName: String, owningFeatureID: FeatureID)

        private enum CodingKeys: String, CodingKey {
            case kind
            case semanticEntityID
            case featureID
            case sceneNodeID
            case persistentName
            case owningFeatureID
        }

        private enum Kind: String, Codable {
            case semanticEntity
            case sourceFeature
            case sceneNode
            case topology
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            switch kind {
            case .semanticEntity:
                self = .semanticEntity(try container.decode(SemanticEntityID.self, forKey: .semanticEntityID))
            case .sourceFeature:
                self = .sourceFeature(try container.decode(FeatureID.self, forKey: .featureID))
            case .sceneNode:
                self = .sceneNode(try container.decode(SceneNodeID.self, forKey: .sceneNodeID))
            case .topology:
                self = .topology(
                    persistentName: try container.decode(String.self, forKey: .persistentName),
                    owningFeatureID: try container.decode(FeatureID.self, forKey: .owningFeatureID)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .semanticEntity(let id):
                try container.encode(Kind.semanticEntity, forKey: .kind)
                try container.encode(id, forKey: .semanticEntityID)
            case .sourceFeature(let id):
                try container.encode(Kind.sourceFeature, forKey: .kind)
                try container.encode(id, forKey: .featureID)
            case .sceneNode(let id):
                try container.encode(Kind.sceneNode, forKey: .kind)
                try container.encode(id, forKey: .sceneNodeID)
            case .topology(let persistentName, let owningFeatureID):
                try container.encode(Kind.topology, forKey: .kind)
                try container.encode(persistentName, forKey: .persistentName)
                try container.encode(owningFeatureID, forKey: .owningFeatureID)
            }
        }

        func validate(
            semanticEntityIDs: Set<SemanticEntityID>,
            cadDocument: CADDocument,
            metadata: ProductMetadata
        ) throws {
            switch self {
            case .semanticEntity(let id):
                guard semanticEntityIDs.contains(id) else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Projection boundary tags must reference an existing semantic entity."
                    )
                }
            case .sourceFeature(let id):
                guard cadDocument.designGraph.nodes[id] != nil else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Projection boundary tags must reference an existing CAD feature."
                    )
                }
            case .sceneNode(let id):
                guard metadata.sceneNodes[id] != nil else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Projection boundary tags must reference an existing scene node."
                    )
                }
            case .topology(let persistentName, let owningFeatureID):
                guard !persistentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Projection boundary topology references must not be empty."
                    )
                }
                guard cadDocument.designGraph.nodes[owningFeatureID] != nil else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Projection boundary topology owners must point to existing CAD features."
                    )
                }
                try validateProjectionTopologyName(
                    persistentName,
                    owningFeatureID: owningFeatureID
                )
            }
        }
    }

    public struct SourceReference: Codable, Hashable, Sendable {
        public var semanticEntityID: SemanticEntityID
        public var featureID: FeatureID
        public var componentID: SelectionComponentID?
        public var ownership: SemanticOwnershipPolicy

        public init(
            semanticEntityID: SemanticEntityID,
            featureID: FeatureID,
            componentID: SelectionComponentID? = nil,
            ownership: SemanticOwnershipPolicy
        ) {
            self.semanticEntityID = semanticEntityID
            self.featureID = featureID
            self.componentID = componentID
            self.ownership = ownership
        }
    }

    public struct SceneReference: Codable, Hashable, Sendable {
        public var semanticEntityID: SemanticEntityID
        public var sceneNodeID: SceneNodeID
        public var objectTypeID: ObjectTypeID?

        public init(
            semanticEntityID: SemanticEntityID,
            sceneNodeID: SceneNodeID,
            objectTypeID: ObjectTypeID? = nil
        ) {
            self.semanticEntityID = semanticEntityID
            self.sceneNodeID = sceneNodeID
            self.objectTypeID = objectTypeID
        }
    }

    public struct TopologyReference: Codable, Hashable, Sendable {
        public var semanticEntityID: SemanticEntityID
        public var persistentName: String
        public var role: TopologyRole
        public var owningFeatureID: FeatureID

        public init(
            semanticEntityID: SemanticEntityID,
            persistentName: String,
            role: TopologyRole,
            owningFeatureID: FeatureID
        ) {
            self.semanticEntityID = semanticEntityID
            self.persistentName = persistentName
            self.role = role
            self.owningFeatureID = owningFeatureID
        }
    }

    public struct BoundaryTag: Codable, Hashable, Sendable {
        public var semanticEntityID: SemanticEntityID
        public var kind: String
        public var target: BoundaryTarget

        public init(
            semanticEntityID: SemanticEntityID,
            kind: String,
            target: BoundaryTarget
        ) {
            self.semanticEntityID = semanticEntityID
            self.kind = kind
            self.target = target
        }
    }

    public var semanticEntities: [ProjectionSemanticEntity]
    public var sourceReferences: [SourceReference]
    public var sceneReferences: [SceneReference]
    public var topologyReferences: [TopologyReference]
    public var boundaryTags: [BoundaryTag]

    public init(
        semanticEntities: [ProjectionSemanticEntity] = [],
        sourceReferences: [SourceReference] = [],
        sceneReferences: [SceneReference] = [],
        topologyReferences: [TopologyReference] = [],
        boundaryTags: [BoundaryTag] = []
    ) {
        self.semanticEntities = semanticEntities
        self.sourceReferences = sourceReferences
        self.sceneReferences = sceneReferences
        self.topologyReferences = topologyReferences
        self.boundaryTags = boundaryTags
    }

    public var hasSourceBoundReferences: Bool {
        !sourceReferences.isEmpty
            || !sceneReferences.isEmpty
            || !topologyReferences.isEmpty
            || !boundaryTags.isEmpty
    }

    public func hasSourceBoundReferences(
        for semanticEntityID: SemanticEntityID
    ) -> Bool {
        sourceReferences.contains { $0.semanticEntityID == semanticEntityID }
            || sceneReferences.contains { $0.semanticEntityID == semanticEntityID }
            || topologyReferences.contains { $0.semanticEntityID == semanticEntityID }
            || boundaryTags.contains { $0.semanticEntityID == semanticEntityID }
    }

    public func validate(
        against cadDocument: CADDocument,
        metadata: ProductMetadata
    ) throws {
        let semanticEntityIDs = semanticEntities.map(\.id)
        let semanticEntityIDSet = Set(semanticEntityIDs)
        guard semanticEntityIDSet.count == semanticEntities.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Projection manifest semantic entity IDs must be unique."
            )
        }
        try validateReferenceUniqueness()
        for semanticEntity in semanticEntities {
            try semanticEntity.validate()
        }
        try validate(sourceReferences, semanticEntityIDs: semanticEntityIDSet, cadDocument: cadDocument)
        try validate(sceneReferences, semanticEntityIDs: semanticEntityIDSet, metadata: metadata)
        try validate(topologyReferences, semanticEntityIDs: semanticEntityIDSet, cadDocument: cadDocument)
        try validate(boundaryTags, semanticEntityIDs: semanticEntityIDSet, cadDocument: cadDocument, metadata: metadata)
        for semanticEntity in semanticEntities {
            let hasReferences = hasSourceBoundReferences(for: semanticEntity.id)
            guard hasReferences == (semanticEntity.dependencyIdentity != nil) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection semantic entity dependency identities must match their source-bound references."
                )
            }
            if let dependencyIdentity = semanticEntity.dependencyIdentity {
                guard dependencyIdentity.documentID == cadDocument.id else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Projection dependency identities must reference their containing CAD document."
                    )
                }
            }
        }
    }

    private func validateReferenceUniqueness() throws {
        guard Set(sourceReferences.map(SourceReferenceTarget.init)).count == sourceReferences.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Projection source mapping targets must be unique per semantic entity."
            )
        }
        guard Set(sceneReferences.map(SceneReferenceTarget.init)).count == sceneReferences.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Projection scene mapping targets must be unique per semantic entity."
            )
        }
        guard Set(topologyReferences.map(TopologyReferenceTarget.init)).count == topologyReferences.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Projection topology mapping targets must be unique per semantic entity."
            )
        }
        guard Set(boundaryTags).count == boundaryTags.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Projection boundary tags must be unique."
            )
        }
    }

    private func validate(
        _ references: [SourceReference],
        semanticEntityIDs: Set<SemanticEntityID>,
        cadDocument: CADDocument
    ) throws {
        for reference in references {
            try requireSemanticEntity(reference.semanticEntityID, in: semanticEntityIDs)
            guard cadDocument.designGraph.nodes[reference.featureID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection source references must point to existing CAD features."
                )
            }
            guard let componentID = reference.componentID else {
                continue
            }
            guard !componentID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection source component references must not be empty."
                )
            }
        }
    }

    private func validate(
        _ references: [SceneReference],
        semanticEntityIDs: Set<SemanticEntityID>,
        metadata: ProductMetadata
    ) throws {
        for reference in references {
            try requireSemanticEntity(reference.semanticEntityID, in: semanticEntityIDs)
            guard let sceneNode = metadata.sceneNodes[reference.sceneNodeID] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection scene references must point to existing scene nodes."
                )
            }
            if let objectTypeID = reference.objectTypeID,
               sceneNode.object?.typeID != objectTypeID {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection scene object type references must match the referenced scene node."
                )
            }
        }
    }

    private func validate(
        _ references: [TopologyReference],
        semanticEntityIDs: Set<SemanticEntityID>,
        cadDocument: CADDocument
    ) throws {
        for reference in references {
            try requireSemanticEntity(reference.semanticEntityID, in: semanticEntityIDs)
            guard !reference.persistentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection topology references must not be empty."
                )
            }
            if cadDocument.designGraph.nodes[reference.owningFeatureID] == nil {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection topology owner references must point to existing CAD features."
                )
            }
            try validateProjectionTopologyName(
                reference.persistentName,
                owningFeatureID: reference.owningFeatureID
            )
        }
    }

    private func validate(
        _ tags: [BoundaryTag],
        semanticEntityIDs: Set<SemanticEntityID>,
        cadDocument: CADDocument,
        metadata: ProductMetadata
    ) throws {
        for tag in tags {
            try requireSemanticEntity(tag.semanticEntityID, in: semanticEntityIDs)
            guard !tag.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Projection boundary tag kinds must not be empty."
                )
            }
            try tag.target.validate(
                semanticEntityIDs: semanticEntityIDs,
                cadDocument: cadDocument,
                metadata: metadata
            )
        }
    }

    private func requireSemanticEntity(
        _ id: SemanticEntityID,
        in semanticEntityIDs: Set<SemanticEntityID>
    ) throws {
        guard semanticEntityIDs.contains(id) else {
            throw DocumentValidationError.invalidProductMetadata(
                "Projection references must point to declared semantic entities."
            )
        }
    }

    private struct SourceReferenceTarget: Hashable {
        var semanticEntityID: SemanticEntityID
        var featureID: FeatureID
        var componentID: SelectionComponentID?

        init(_ reference: SourceReference) {
            semanticEntityID = reference.semanticEntityID
            featureID = reference.featureID
            componentID = reference.componentID
        }
    }

    private struct SceneReferenceTarget: Hashable {
        var semanticEntityID: SemanticEntityID
        var sceneNodeID: SceneNodeID

        init(_ reference: SceneReference) {
            semanticEntityID = reference.semanticEntityID
            sceneNodeID = reference.sceneNodeID
        }
    }

    private struct TopologyReferenceTarget: Hashable {
        var semanticEntityID: SemanticEntityID
        var persistentName: String
        var owningFeatureID: FeatureID

        init(_ reference: TopologyReference) {
            semanticEntityID = reference.semanticEntityID
            persistentName = reference.persistentName
            owningFeatureID = reference.owningFeatureID
        }
    }
}

private func validateProjectionTopologyName(
    _ value: String,
    owningFeatureID: FeatureID
) throws {
    let persistentName: PersistentName
    do {
        persistentName = try GeneratedTopologyPersistentNameParser().parse(
            value,
            operationName: "Projection manifest"
        )
    } catch {
        throw DocumentValidationError.invalidProductMetadata(
            "Projection topology references must use a valid persistent topology name."
        )
    }
    guard persistentName.components.contains(where: { component in
        if case .feature(let featureID) = component {
            return featureID == owningFeatureID
        }
        return false
    }) else {
        throw DocumentValidationError.invalidProductMetadata(
            "Projection topology persistent names must contain their owning CAD feature."
        )
    }
}
