import Foundation
import SwiftCAD
import RupaCoreTypes

public enum ValidationSubjectReference: Codable, Hashable, Sendable {
    case document(DocumentID)
    case feature(documentID: DocumentID, featureID: FeatureID)
    case sceneNode(documentID: DocumentID, sceneNodeID: SceneNodeID)
    case semanticEntity(
        documentID: DocumentID,
        extensionID: SemanticExtensionID,
        entityID: SemanticEntityID
    )
    case generatedTopology(
        documentID: DocumentID,
        owningFeatureID: FeatureID,
        persistentName: String
    )
    case artifact(MaterializedArtifactReference)
    case meshBody(artifact: MeshArtifactReference, bodyID: BodyID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case documentID
        case featureID
        case sceneNodeID
        case extensionID
        case entityID
        case owningFeatureID
        case persistentName
        case artifact
        case bodyID
    }

    private enum Kind: String, Codable {
        case document
        case feature
        case sceneNode
        case semanticEntity
        case generatedTopology
        case artifact
        case meshBody
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .document:
            self = .document(try container.decode(DocumentID.self, forKey: .documentID))
        case .feature:
            self = .feature(
                documentID: try container.decode(DocumentID.self, forKey: .documentID),
                featureID: try container.decode(FeatureID.self, forKey: .featureID)
            )
        case .sceneNode:
            self = .sceneNode(
                documentID: try container.decode(DocumentID.self, forKey: .documentID),
                sceneNodeID: try container.decode(SceneNodeID.self, forKey: .sceneNodeID)
            )
        case .semanticEntity:
            self = .semanticEntity(
                documentID: try container.decode(DocumentID.self, forKey: .documentID),
                extensionID: try container.decode(SemanticExtensionID.self, forKey: .extensionID),
                entityID: try container.decode(SemanticEntityID.self, forKey: .entityID)
            )
        case .generatedTopology:
            self = .generatedTopology(
                documentID: try container.decode(DocumentID.self, forKey: .documentID),
                owningFeatureID: try container.decode(FeatureID.self, forKey: .owningFeatureID),
                persistentName: try container.decode(String.self, forKey: .persistentName)
            )
        case .artifact:
            self = .artifact(try container.decode(MaterializedArtifactReference.self, forKey: .artifact))
        case .meshBody:
            self = .meshBody(
                artifact: try container.decode(MeshArtifactReference.self, forKey: .artifact),
                bodyID: try container.decode(BodyID.self, forKey: .bodyID)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .document(let documentID):
            try container.encode(Kind.document, forKey: .kind)
            try container.encode(documentID, forKey: .documentID)
        case .feature(let documentID, let featureID):
            try container.encode(Kind.feature, forKey: .kind)
            try container.encode(documentID, forKey: .documentID)
            try container.encode(featureID, forKey: .featureID)
        case .sceneNode(let documentID, let sceneNodeID):
            try container.encode(Kind.sceneNode, forKey: .kind)
            try container.encode(documentID, forKey: .documentID)
            try container.encode(sceneNodeID, forKey: .sceneNodeID)
        case .semanticEntity(let documentID, let extensionID, let entityID):
            try container.encode(Kind.semanticEntity, forKey: .kind)
            try container.encode(documentID, forKey: .documentID)
            try container.encode(extensionID, forKey: .extensionID)
            try container.encode(entityID, forKey: .entityID)
        case .generatedTopology(let documentID, let owningFeatureID, let persistentName):
            try container.encode(Kind.generatedTopology, forKey: .kind)
            try container.encode(documentID, forKey: .documentID)
            try container.encode(owningFeatureID, forKey: .owningFeatureID)
            try container.encode(persistentName, forKey: .persistentName)
        case .artifact(let artifact):
            try container.encode(Kind.artifact, forKey: .kind)
            try container.encode(artifact, forKey: .artifact)
        case .meshBody(let artifact, let bodyID):
            try container.encode(Kind.meshBody, forKey: .kind)
            try container.encode(artifact, forKey: .artifact)
            try container.encode(bodyID, forKey: .bodyID)
        }
    }

    public var documentID: DocumentID {
        switch self {
        case .document(let id):
            id
        case .feature(let id, _),
             .sceneNode(let id, _),
             .semanticEntity(let id, _, _),
             .generatedTopology(let id, _, _):
            id
        case .artifact(let artifact):
            artifact.documentID
        case .meshBody(let artifact, _):
            artifact.documentID
        }
    }

    public func validate() throws {
        switch self {
        case .document, .feature, .sceneNode:
            break
        case .semanticEntity(_, _, let entityID):
            try entityID.validate()
        case .generatedTopology(_, let owningFeatureID, let persistentName):
            let parsedName: PersistentName
            do {
                parsedName = try GeneratedTopologyPersistentNameParser().parse(
                    persistentName,
                    operationName: "Validation subject"
                )
            } catch {
                throw invalidSubject("Validation topology subjects require a valid persistent name.")
            }
            guard parsedName.components.contains(where: { component in
                if case .feature(let featureID) = component {
                    return featureID == owningFeatureID
                }
                return false
            }) else {
                throw invalidSubject(
                    "Validation topology subjects must contain their owning feature in the persistent name."
                )
            }
        case .artifact(let artifact):
            guard artifact.documentID == documentID else {
                throw invalidSubject("Validation artifact subjects must preserve their document identity.")
            }
        case .meshBody(let artifact, _):
            try artifact.validate()
        }
    }

    private func invalidSubject(_ message: String) -> ReferenceValidationError {
        ReferenceValidationError(code: .invalidShape, message: message)
    }
}
