import Foundation
import SwiftCAD
import RupaCoreTypes

public enum SourceDependencySubject: Codable, Hashable, Sendable {
    case cadDocument(DocumentID)
    case rupaDocument(DocumentID)
    case linkedDocument(DocumentID)
    case semanticEntity(
        documentID: DocumentID,
        namespace: SemanticNamespaceID,
        extensionID: SemanticExtensionID,
        entityID: SemanticEntityID
    )
    case external(namespace: String, logicalID: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case documentID
        case namespace
        case extensionID
        case entityID
        case logicalID
    }

    private enum Kind: String, Codable {
        case cadDocument
        case rupaDocument
        case linkedDocument
        case semanticEntity
        case external
    }

    public var sortKey: String {
        switch self {
        case .cadDocument(let id):
            "cad:\(id.description)"
        case .rupaDocument(let id):
            "rupa:\(id.description)"
        case .linkedDocument(let id):
            "linked:\(id.description)"
        case .semanticEntity(let documentID, let namespace, let extensionID, let entityID):
            "semantic:\(documentID.description):\(namespace.rawValue):\(extensionID.rawValue.uuidString):\(entityID.rawValue)"
        case .external(let namespace, let logicalID):
            "external:\(namespace):\(logicalID)"
        }
    }

    public func validate() throws {
        switch self {
        case .cadDocument, .rupaDocument, .linkedDocument:
            break
        case .semanticEntity(_, let namespace, _, let entityID):
            try namespace.validate()
            try entityID.validate()
        case .external(let namespace, let logicalID):
            guard !namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !logicalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ReferenceValidationError(
                    code: .invalidIdentity,
                    message: "External dependencies require namespace and logical ID values."
                )
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .cadDocument:
            self = .cadDocument(try container.decode(DocumentID.self, forKey: .documentID))
        case .rupaDocument:
            self = .rupaDocument(try container.decode(DocumentID.self, forKey: .documentID))
        case .linkedDocument:
            self = .linkedDocument(try container.decode(DocumentID.self, forKey: .documentID))
        case .semanticEntity:
            self = .semanticEntity(
                documentID: try container.decode(DocumentID.self, forKey: .documentID),
                namespace: try container.decode(SemanticNamespaceID.self, forKey: .namespace),
                extensionID: try container.decode(SemanticExtensionID.self, forKey: .extensionID),
                entityID: try container.decode(SemanticEntityID.self, forKey: .entityID)
            )
        case .external:
            self = .external(
                namespace: try container.decode(String.self, forKey: .namespace),
                logicalID: try container.decode(String.self, forKey: .logicalID)
            )
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cadDocument(let documentID):
            try container.encode(Kind.cadDocument, forKey: .kind)
            try container.encode(documentID, forKey: .documentID)
        case .rupaDocument(let documentID):
            try container.encode(Kind.rupaDocument, forKey: .kind)
            try container.encode(documentID, forKey: .documentID)
        case .linkedDocument(let documentID):
            try container.encode(Kind.linkedDocument, forKey: .kind)
            try container.encode(documentID, forKey: .documentID)
        case .semanticEntity(let documentID, let namespace, let extensionID, let entityID):
            try container.encode(Kind.semanticEntity, forKey: .kind)
            try container.encode(documentID, forKey: .documentID)
            try container.encode(namespace, forKey: .namespace)
            try container.encode(extensionID, forKey: .extensionID)
            try container.encode(entityID, forKey: .entityID)
        case .external(let namespace, let logicalID):
            try container.encode(Kind.external, forKey: .kind)
            try container.encode(namespace, forKey: .namespace)
            try container.encode(logicalID, forKey: .logicalID)
        }
    }
}
