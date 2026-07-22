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
    case stableTopology(
        documentID: DocumentID,
        reference: StableSubshapeReference
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
        case stableReference
        case artifact
        case bodyID
    }

    private enum Kind: String, Codable {
        case document
        case feature
        case sceneNode
        case semanticEntity
        case stableTopology
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
        case .stableTopology:
            self = .stableTopology(
                documentID: try container.decode(DocumentID.self, forKey: .documentID),
                reference: try container.decode(
                    StableSubshapeReference.self,
                    forKey: .stableReference
                )
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
        case .stableTopology(let documentID, let reference):
            try container.encode(Kind.stableTopology, forKey: .kind)
            try container.encode(documentID, forKey: .documentID)
            try container.encode(reference, forKey: .stableReference)
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
             .stableTopology(let id, _):
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
        case .stableTopology(_, let reference):
            try reference.validate()
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
